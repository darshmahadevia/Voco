use crate::{
    audio::Recorder,
    cleanup,
    domain::{CaptureMode, ModelId, OutputMode, Session},
    gesture::Action,
    models,
    platform::{self, FocusTarget, Permissions, ShortcutMonitor},
    speech::Engine,
    storage::Settings,
};
use anyhow::{Context, Result};
use crossbeam_channel::{Receiver, Sender, unbounded};
use std::{
    collections::VecDeque,
    path::PathBuf,
    sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
    },
    time::{Duration, Instant},
};

#[derive(Clone, Debug)]
pub enum EngineStatus {
    Missing,
    Loading,
    Ready,
    Error(String),
}

pub struct Transcript {
    pub text: String,
    pub time: String,
}

pub struct Download {
    pub id: ModelId,
    pub progress: f32,
    pub file: String,
    pub cancel: Arc<AtomicBool>,
    generation: u64,
}

enum Work {
    Load {
        generation: u64,
        id: ModelId,
    },
    Transcribe {
        generation: u64,
        samples: Vec<f32>,
        cancel: Arc<AtomicBool>,
    },
}
enum Event {
    Loaded {
        generation: u64,
        result: std::result::Result<(), String>,
    },
    Transcribed {
        generation: u64,
        result: std::result::Result<String, String>,
    },
    Progress {
        generation: u64,
        progress: f32,
        file: String,
    },
    Downloaded {
        generation: u64,
        id: ModelId,
        result: std::result::Result<(), String>,
    },
}

#[derive(Default)]
pub struct Generation(u64);
impl Generation {
    pub fn next_id(&mut self) -> u64 {
        self.0 = self.0.wrapping_add(1);
        self.0
    }
    pub fn accepts(&self, id: u64) -> bool {
        self.0 == id
    }
}

enum Target {
    Native(FocusTarget),
    Practice(crate::practice::PracticeTarget),
}

pub struct Controller {
    pub root: PathBuf,
    pub settings: Settings,
    pub session: Session,
    pub engine: EngineStatus,
    pub permissions: Permissions,
    pub history: VecDeque<Transcript>,
    pub last_raw: String,
    pub notice: String,
    pub download: Option<Download>,
    pub show_dashboard: bool,
    pub shortcut_running: bool,
    pub practice_update: Option<(String, usize)>,
    pub practice_snapshot: Option<crate::practice::PracticeTarget>,
    recorder: Option<Recorder>,
    target: Option<Target>,
    monitor: Option<ShortcutMonitor>,
    actions: Receiver<Action>,
    action_sender: Sender<Action>,
    work: Sender<Work>,
    events: Receiver<Event>,
    event_sender: Sender<Event>,
    active_model: Option<ModelId>,
    model_generation: Generation,
    session_generation: Generation,
    download_generation: Generation,
    armed_at: Option<Instant>,
    started_at: Option<Instant>,
    finishing_at: Option<Instant>,
    inference_cancel: Option<Arc<AtomicBool>>,
    pending_insert: Option<(String, Instant)>,
    output_mode: OutputMode,
    last_permission_check: Instant,
}

impl Controller {
    pub fn new(root: PathBuf) -> Result<Self> {
        let settings = Settings::load(&root)?;
        let (work, work_rx) = unbounded();
        let (event_sender, events) = unbounded();
        let (action_sender, actions) = unbounded();
        let models_root = root.join("models");
        let sender = event_sender.clone();
        std::thread::Builder::new()
            .name("voco-inference".into())
            .spawn(move || {
                let mut engine: Option<Engine> = None;
                while let Ok(work) = work_rx.recv() {
                    match work {
                        Work::Load { generation, id } => {
                            let result = Engine::load(id, &models_root)
                                .map(|loaded| {
                                    engine = Some(loaded);
                                })
                                .map_err(|e| format!("{e:#}"));
                            if sender.send(Event::Loaded { generation, result }).is_err() {
                                break;
                            }
                        }
                        Work::Transcribe {
                            generation,
                            samples,
                            cancel,
                        } => {
                            let result = engine
                                .as_mut()
                                .context("The speech engine is unavailable.")
                                .and_then(|engine| engine.transcribe_cancellable(&samples, &cancel))
                                .map_err(|e| format!("{e:#}"));
                            if sender
                                .send(Event::Transcribed { generation, result })
                                .is_err()
                            {
                                break;
                            }
                        }
                    }
                }
            })?;
        let mut this = Self {
            root,
            settings,
            session: Session::Idle,
            engine: EngineStatus::Missing,
            permissions: platform::permissions(),
            history: VecDeque::new(),
            last_raw: String::new(),
            notice: String::new(),
            download: None,
            show_dashboard: false,
            shortcut_running: false,
            practice_update: None,
            practice_snapshot: None,
            recorder: None,
            target: None,
            monitor: None,
            actions,
            action_sender,
            work,
            events,
            event_sender,
            active_model: None,
            model_generation: Generation::default(),
            session_generation: Generation::default(),
            download_generation: Generation::default(),
            armed_at: None,
            started_at: None,
            finishing_at: None,
            inference_cancel: None,
            pending_insert: None,
            output_mode: OutputMode::Fast,
            last_permission_check: Instant::now() - Duration::from_secs(2),
        };
        this.refresh_permissions();
        this.load_model(this.settings.selected_model);
        Ok(this)
    }

    pub fn ready(&self) -> bool {
        matches!(self.engine, EngineStatus::Ready)
            && self.permissions.microphone
            && self.permissions.accessibility
            && self.shortcut_running
    }
    pub fn level(&self) -> f32 {
        self.recorder.as_ref().map_or(0.0, Recorder::level)
    }
    pub fn status(&self) -> &str {
        match &self.session {
            Session::Armed => "Starting",
            Session::Listening { .. } => "Listening",
            Session::Finishing => "Transcribing",
            Session::Recovery { .. } => "Words saved for copying",
            Session::Idle => match &self.engine {
                EngineStatus::Missing => "Choose a speech model to finish setup",
                EngineStatus::Loading => "Loading speech model",
                EngineStatus::Error(_) => "Speech model needs attention",
                EngineStatus::Ready if self.ready() => "Ready to dictate",
                EngineStatus::Ready => "Finish microphone and keyboard setup",
            },
        }
    }
    pub fn save(&mut self) {
        if let Err(error) = self.settings.save(&self.root) {
            self.notice = format!("Could not save settings. {error}");
        }
    }
    pub fn set_retention(&mut self, keep: bool) {
        self.settings.keep_last_transcript = keep;
        if !keep {
            self.history.clear();
            self.last_raw.clear();
        }
        self.save();
    }
    pub fn load_model(&mut self, id: ModelId) {
        if self.session.active() || matches!(self.engine, EngineStatus::Loading) {
            return;
        }
        self.settings.selected_model = id;
        self.save();
        let generation = self.model_generation.next_id();
        if !models::installed(&self.root.join("models"), id) {
            self.engine = EngineStatus::Missing;
            return;
        }
        self.engine = EngineStatus::Loading;
        if self.work.send(Work::Load { generation, id }).is_err() {
            self.engine = EngineStatus::Error("The inference worker stopped. Restart Voco.".into());
        }
    }
    pub fn download_model(&mut self, id: ModelId) {
        if self.download.is_some() || self.session.active() {
            return;
        }
        let generation = self.download_generation.next_id();
        let cancel = Arc::new(AtomicBool::new(false));
        self.download = Some(Download {
            id,
            progress: 0.0,
            file: "Starting download".into(),
            cancel: cancel.clone(),
            generation,
        });
        let sender = self.event_sender.clone();
        let root = self.root.join("models");
        std::thread::spawn(move || {
            let result = models::download(&root, id, &cancel, |progress, file| {
                let _ = sender.send(Event::Progress {
                    generation,
                    progress,
                    file,
                });
            })
            .map_err(|e| format!("{e:#}"));
            let _ = sender.send(Event::Downloaded {
                generation,
                id,
                result,
            });
        });
    }
    pub fn cancel_download(&mut self) {
        if let Some(download) = &self.download {
            download.cancel.store(true, Ordering::Relaxed);
        }
    }
    pub fn refresh_permissions(&mut self) {
        self.permissions = platform::permissions();
        if !self.permissions.accessibility {
            self.monitor = None;
            self.shortcut_running = false;
        } else if self
            .monitor
            .as_ref()
            .is_some_and(|monitor| !monitor.is_running())
        {
            self.shortcut_running = false;
            if let Some(monitor) = &self.monitor {
                monitor.retry();
            }
        } else if self.monitor.is_none() {
            match platform::start_shortcuts(self.action_sender.clone()) {
                Ok(monitor) => {
                    self.monitor = Some(monitor);
                    self.shortcut_running = true;
                }
                Err(error) => {
                    self.notice = format!("Keyboard monitoring could not start. {error}");
                    self.shortcut_running = false;
                }
            }
        }
        if let Some(monitor) = &self.monitor {
            self.shortcut_running = monitor.is_running();
        }
        if (!self.permissions.accessibility || !self.permissions.microphone)
            && matches!(
                self.session,
                Session::Armed | Session::Listening { .. } | Session::Finishing
            )
        {
            self.cancel();
            self.notice =
                "Microphone or keyboard permission was turned off. Dictation stopped.".into();
        }
        self.last_permission_check = Instant::now();
    }
    pub fn tick(&mut self) {
        if self.last_permission_check.elapsed() >= Duration::from_secs(1) {
            self.refresh_permissions();
        }
        if let Some(message) = self.recorder.as_ref().and_then(Recorder::error) {
            self.cancel();
            self.recover(message, String::new());
        }
        if self.recorder.as_ref().is_some_and(Recorder::at_limit) {
            self.finish();
            self.notice = "Reached the ten minute recording limit. Transcribing your words.".into();
        }
        // Keyboard cancellation wins over an inference completion received in the same frame.
        while let Ok(action) = self.actions.try_recv() {
            self.action(action);
        }
        if matches!(self.session, Session::Armed)
            && self
                .armed_at
                .is_some_and(|at| at.elapsed() >= Duration::from_millis(140))
        {
            self.begin(CaptureMode::Hold);
        }
        if self
            .finishing_at
            .is_some_and(|at| at.elapsed() >= Duration::from_secs(120))
        {
            self.cancel();
            self.recover(
                "Speech recognition took too long. Try a shorter dictation or restart Voco.".into(),
                String::new(),
            );
        }
        while let Ok(event) = self.events.try_recv() {
            match event {
                Event::Loaded { generation, result }
                    if self.model_generation.accepts(generation) =>
                {
                    match result {
                        Ok(()) => {
                            self.active_model = Some(self.settings.selected_model);
                            self.engine = EngineStatus::Ready;
                        }
                        Err(error) => {
                            if let Some(previous) = self.active_model {
                                self.settings.selected_model = previous;
                                self.engine = EngineStatus::Ready;
                                self.notice = format!("Could not switch speech models. {error}");
                                self.save();
                            } else {
                                self.engine = EngineStatus::Error(error);
                            }
                        }
                    }
                }
                Event::Transcribed { generation, result }
                    if self.session_generation.accepts(generation)
                        && matches!(self.session, Session::Finishing) =>
                {
                    self.finishing_at = None;
                    self.inference_cancel = None;
                    match result {
                        Ok(raw) => self.complete(raw),
                        Err(message) => self.recover(message, String::new()),
                    }
                }
                Event::Progress {
                    generation,
                    progress,
                    file,
                } => {
                    if let Some(download) = self
                        .download
                        .as_mut()
                        .filter(|d| d.generation == generation)
                    {
                        download.progress = progress;
                        download.file = file;
                    }
                }
                Event::Downloaded {
                    generation,
                    id,
                    result,
                } if self.download_generation.accepts(generation) => {
                    let cancelled = self
                        .download
                        .as_ref()
                        .is_some_and(|d| d.cancel.load(Ordering::Relaxed));
                    self.download = None;
                    match result {
                        Ok(()) => {
                            if matches!(self.session, Session::Idle) {
                                self.load_model(id);
                            }
                        }
                        Err(message) => {
                            if !cancelled {
                                self.notice = format!("Download failed. {message}");
                            }
                        }
                    }
                }
                _ => {}
            }
        }
        if self.pending_insert.as_ref().is_some_and(|(_, at)| {
            !platform::shortcut_modifiers_down() || at.elapsed() >= Duration::from_millis(500)
        }) && let Some((text, _)) = self.pending_insert.take()
        {
            if platform::shortcut_modifiers_down() {
                self.recover(
                    "Release shortcut keys before inserting. Copy your transcript instead.".into(),
                    text,
                );
            } else {
                self.insert_text(text);
            }
        }
    }
    pub fn action(&mut self, action: Action) {
        match action {
            Action::Escape => self.cancel(),
            Action::Cancelled => {
                if matches!(
                    self.session,
                    Session::Armed
                        | Session::Listening {
                            mode: CaptureMode::Hold
                        }
                ) {
                    self.cancel();
                }
            }
            Action::Pressed if matches!(self.session, Session::Idle) => {
                if self.prepare_target() {
                    self.session = Session::Armed;
                    self.armed_at = Some(Instant::now());
                }
            }
            Action::Released => {
                if matches!(
                    self.session,
                    Session::Armed
                        | Session::Listening {
                            mode: CaptureMode::Hold
                        }
                ) {
                    self.finish();
                }
            }
            Action::ToggleContinuous => match self.session {
                Session::Listening {
                    mode: CaptureMode::Continuous,
                } => self.finish(),
                Session::Listening {
                    mode: CaptureMode::Hold,
                } => {
                    self.session = Session::Listening {
                        mode: CaptureMode::Continuous,
                    }
                }
                Session::Armed => self.begin(CaptureMode::Continuous),
                Session::Idle => {
                    if self.prepare_target() {
                        self.begin(CaptureMode::Continuous);
                    }
                }
                _ => {}
            },
            _ => {}
        }
    }
    fn prepare_target(&mut self) -> bool {
        if !self.ready() {
            self.show_dashboard = true;
            return false;
        }
        let target = if platform::voco_is_focused() {
            self.practice_snapshot
                .clone()
                .map(Target::Practice)
                .context("Click inside the practice field before dictating into Voco.")
        } else {
            FocusTarget::capture().map(Target::Native)
        };
        match target {
            Ok(target) => {
                self.target = Some(target);
                self.output_mode = self.settings.output_mode;
                self.session_generation.next_id();
                self.notice.clear();
                self.last_raw.clear();
                true
            }
            Err(error) => {
                self.notice = error.to_string();
                self.show_dashboard = true;
                false
            }
        }
    }
    fn begin(&mut self, mode: CaptureMode) {
        self.armed_at = None;
        match Recorder::start() {
            Ok(recorder) => {
                self.recorder = Some(recorder);
                self.started_at = Some(Instant::now());
                self.session = Session::Listening { mode };
            }
            Err(error) => self.recover(error.to_string(), String::new()),
        }
    }
    fn finish(&mut self) {
        self.armed_at = None;
        let Some(recorder) = self.recorder.take() else {
            self.cancel();
            return;
        };
        match recorder.finish() {
            Ok(samples) if !samples.is_empty() => {
                self.session = Session::Finishing;
                self.finishing_at = Some(Instant::now());
                let cancel = Arc::new(AtomicBool::new(false));
                self.inference_cancel = Some(cancel.clone());
                if self
                    .work
                    .send(Work::Transcribe {
                        generation: self.session_generation.0,
                        samples,
                        cancel,
                    })
                    .is_err()
                {
                    self.recover(
                        "The inference worker stopped. Restart Voco.".into(),
                        String::new(),
                    );
                }
            }
            Ok(_) => self.cancel(),
            Err(error) => self.recover(error.to_string(), String::new()),
        }
    }
    fn complete(&mut self, raw: String) {
        if self.settings.keep_last_transcript {
            self.last_raw = raw.clone();
        }
        let (text, notice) = cleanup::polish(&raw, self.output_mode);
        self.notice = notice;
        if text.is_empty() {
            self.cancel();
            return;
        }
        self.pending_insert = Some((text, Instant::now()));
    }
    fn insert_text(&mut self, text: String) {
        let result = self
            .target
            .take()
            .context("The original text field is unavailable.")
            .and_then(|target| match target {
                Target::Native(target) => target.insert(&text),
                Target::Practice(target) => {
                    anyhow::ensure!(
                        platform::voco_is_focused(),
                        "The focused application changed. Copy your transcript instead."
                    );
                    let current = self.practice_snapshot.as_ref().context(
                        "The practice field lost keyboard focus. Copy your transcript instead.",
                    )?;
                    self.practice_update = Some(target.replace(current, &text)?);
                    Ok(())
                }
            });
        match result {
            Ok(()) => {
                self.settings.record(
                    &text,
                    self.started_at.map_or(0.0, |at| at.elapsed().as_secs_f64()),
                );
                self.retain(text);
                self.session = Session::Idle;
                self.started_at = None;
                self.save();
            }
            Err(error) => {
                self.retain(text.clone());
                self.recover(error.to_string(), text);
            }
        }
    }
    fn retain(&mut self, text: String) {
        if self.settings.keep_last_transcript {
            self.history.push_front(Transcript {
                text,
                time: chrono::Local::now().format("%I:%M %p").to_string(),
            });
            self.history.truncate(50);
        }
    }
    fn recover(&mut self, message: String, text: String) {
        self.recorder = None;
        self.target = None;
        self.armed_at = None;
        self.finishing_at = None;
        self.session = Session::Recovery { message, text };
        self.show_dashboard = true;
    }
    pub fn cancel(&mut self) {
        if let Some(cancel) = self.inference_cancel.take() {
            cancel.store(true, Ordering::Relaxed);
        }
        self.session_generation.next_id();
        self.recorder = None;
        self.target = None;
        self.armed_at = None;
        self.finishing_at = None;
        self.pending_insert = None;
        self.started_at = None;
        self.session = Session::Idle;
    }
    pub fn copy_recovery(&mut self) {
        if let Session::Recovery { text, .. } = &self.session {
            match platform::copy_text(text) {
                Ok(()) => self.cancel(),
                Err(error) => self.notice = error.to_string(),
            }
        }
    }
}
impl Drop for Controller {
    fn drop(&mut self) {
        self.cancel_download();
        self.cancel();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn cancelled_generation_rejects_late_transcript() {
        let mut generation = Generation::default();
        let recording = generation.next_id();
        assert!(generation.accepts(recording));
        generation.next_id();
        assert!(!generation.accepts(recording));
        let next_recording = generation.next_id();
        assert!(!generation.accepts(recording));
        assert!(generation.accepts(next_recording));
    }
}
