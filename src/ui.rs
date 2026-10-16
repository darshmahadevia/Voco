use crate::{
    controller::{Controller, EngineStatus},
    domain::{ModelId, OutputMode, Session},
    models, platform,
};
use anyhow::Result;
use eframe::egui::{
    self, Color32, FontData, FontDefinitions, FontFamily, FontId, RichText, Stroke, Vec2,
};
use std::{
    path::PathBuf,
    sync::Arc,
    time::{Duration, Instant},
};
use tray_icon::{
    TrayIcon, TrayIconBuilder,
    menu::{Menu, MenuEvent, MenuItem, PredefinedMenuItem, Submenu},
};

const BACKGROUND: Color32 = Color32::from_rgb(10, 10, 10);
const ACCENT: Color32 = Color32::from_rgb(255, 116, 47);
const TEXT: Color32 = Color32::from_rgb(242, 240, 236);
const MUTED: Color32 = Color32::from_rgb(185, 184, 181);

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Page {
    Home,
    Transcripts,
    Stats,
    Settings,
}
#[derive(Clone, Copy, PartialEq, Eq)]
enum Tab {
    Output,
    Models,
    Access,
    Dictation,
}

pub struct VocoApp {
    controller: Controller,
    page: Page,
    tab: Tab,
    tray: TrayIcon,
    _application_menu: Menu,
    copy_menu: MenuItem,
    overlay: platform::Overlay,
    visible: bool,
    quitting: bool,
    practice: String,
    ime_composing: bool,
    search: String,
    copied_until: Option<Instant>,
    verification: Option<Verification>,
}

struct Verification {
    directory: PathBuf,
    started: Instant,
    stage: usize,
    captures: usize,
    practice_ready: Option<Instant>,
    practice_verified: bool,
}

impl VocoApp {
    pub fn new(
        cc: &eframe::CreationContext<'_>,
        root: PathBuf,
        show: bool,
        verification: Option<PathBuf>,
    ) -> Result<Self> {
        let ctx = &cc.egui_ctx;
        let mut fonts = FontDefinitions::default();
        fonts.font_data.insert(
            "Manrope".into(),
            Arc::new(FontData::from_static(include_bytes!(
                "../Resources/Fonts/Manrope-Regular.ttf"
            ))),
        );
        fonts
            .families
            .entry(FontFamily::Proportional)
            .or_default()
            .insert(0, "Manrope".into());
        ctx.set_fonts(fonts);
        let mut style = (*ctx.style()).clone();
        style.visuals = egui::Visuals::dark();
        style.visuals.panel_fill = BACKGROUND;
        style.visuals.window_fill = BACKGROUND;
        style.visuals.extreme_bg_color = Color32::from_rgb(20, 20, 20);
        style.visuals.override_text_color = Some(TEXT);
        style.visuals.selection.bg_fill = Color32::from_rgb(80, 40, 24);
        style.visuals.selection.stroke = Stroke::new(1.0, ACCENT);
        style.visuals.widgets.active.bg_fill = Color32::from_rgb(56, 37, 29);
        style.visuals.widgets.active.fg_stroke = Stroke::new(1.0, ACCENT);
        style.spacing.item_spacing = Vec2::new(12.0, 12.0);
        style.spacing.button_padding = Vec2::new(14.0, 8.0);
        style
            .text_styles
            .insert(egui::TextStyle::Body, FontId::proportional(14.0));
        style
            .text_styles
            .insert(egui::TextStyle::Button, FontId::proportional(13.0));
        style
            .text_styles
            .insert(egui::TextStyle::Heading, FontId::proportional(30.0));
        ctx.set_style(style);
        let menu = Menu::new();
        menu.append(&MenuItem::with_id(
            "status",
            "Voco · Local dictation",
            false,
            None,
        ))?;
        menu.append(&PredefinedMenuItem::separator())?;
        for (id, label, shortcut) in [
            ("home", "Open Dashboard", "Cmd+1"),
            ("transcripts", "Transcripts", "Cmd+2"),
            ("stats", "Stats", "Cmd+3"),
            ("settings", "Settings…", "Cmd+Comma"),
        ] {
            menu.append(&MenuItem::with_id(id, label, true, Some(shortcut.parse()?)))?;
        }
        let copy_menu = MenuItem::with_id("copy", "Copy last transcript", false, None);
        menu.append(&copy_menu)?;
        menu.append(&PredefinedMenuItem::separator())?;
        menu.append(&MenuItem::with_id(
            "quit",
            "Quit Voco",
            true,
            Some("Cmd+Q".parse()?),
        ))?;
        let image =
            image::load_from_memory(include_bytes!("../Resources/Brand/voco-trayTemplate.png"))?
                .into_rgba8();
        let (width, height) = image.dimensions();
        let icon = tray_icon::Icon::from_rgba(image.into_raw(), width, height)?;
        let tray = TrayIconBuilder::new()
            .with_icon(icon)
            .with_icon_as_template(true)
            .with_tooltip("Voco · Local dictation")
            .with_menu(Box::new(menu))
            .build()?;
        let application_menu = Menu::new();
        let app_menu = Submenu::new("Voco", true);
        app_menu.append(&MenuItem::with_id(
            "quit",
            "Quit Voco",
            true,
            Some("Cmd+Q".parse()?),
        ))?;
        application_menu.append(&app_menu)?;
        let navigation = Submenu::new("Navigate", true);
        for (id, label, shortcut) in [
            ("home", "Open Dashboard", "Cmd+1"),
            ("transcripts", "Transcripts", "Cmd+2"),
            ("stats", "Stats", "Cmd+3"),
            ("settings", "Settings…", "Cmd+Comma"),
        ] {
            navigation.append(&MenuItem::with_id(id, label, true, Some(shortcut.parse()?)))?;
        }
        application_menu.append(&navigation)?;
        let edit = Submenu::new("Edit", true);
        edit.append(&PredefinedMenuItem::undo(None))?;
        edit.append(&PredefinedMenuItem::redo(None))?;
        edit.append(&PredefinedMenuItem::separator())?;
        edit.append(&PredefinedMenuItem::cut(None))?;
        edit.append(&PredefinedMenuItem::copy(None))?;
        edit.append(&PredefinedMenuItem::paste(None))?;
        edit.append(&PredefinedMenuItem::select_all(None))?;
        application_menu.append(&edit)?;
        application_menu.init_for_nsapp();
        platform::hide_dock();
        let overlay = platform::Overlay::new()?;
        let controller = Controller::new(root)?;
        Ok(Self {
            controller,
            page: Page::Home,
            tab: Tab::Output,
            tray,
            _application_menu: application_menu,
            copy_menu,
            overlay,
            visible: show,
            quitting: false,
            practice: String::new(),
            ime_composing: false,
            search: String::new(),
            copied_until: None,
            verification: verification.map(|directory| Verification {
                directory,
                started: Instant::now(),
                stage: 0,
                captures: 0,
                practice_ready: None,
                practice_verified: false,
            }),
        })
    }

    fn show(&mut self, ctx: &egui::Context, page: Page) {
        self.page = page;
        self.visible = true;
        ctx.send_viewport_cmd(egui::ViewportCommand::Visible(true));
        platform::activate_dashboard();
        ctx.send_viewport_cmd(egui::ViewportCommand::Focus);
    }
    fn result(&mut self, result: Result<()>) {
        if let Err(error) = result {
            self.controller.notice = error.to_string();
        }
    }

    fn header(ui: &mut egui::Ui, title: &str, description: &str) {
        ui.heading(title);
        ui.add_space(4.0);
        ui.label(RichText::new(description).color(MUTED));
        ui.add_space(20.0);
    }
    fn primary(ui: &mut egui::Ui, text: &str) -> egui::Response {
        ui.add(
            egui::Button::new(RichText::new(text).color(BACKGROUND))
                .fill(TEXT)
                .corner_radius(18),
        )
    }
    fn copy(&mut self, text: &str) {
        match platform::copy_text(text) {
            Ok(()) => {
                self.copied_until = Some(Instant::now() + Duration::from_secs(2));
            }
            Err(error) => self.controller.notice = format!("Could not copy. {error}"),
        }
    }
    fn model_rows(&mut self, ui: &mut egui::Ui) {
        let busy = self.controller.session.active();
        for id in ModelId::ALL {
            ui.horizontal(|ui| {
                ui.vertical(|ui| {
                    ui.label(RichText::new(id.label()).size(16.0));
                    let description = match id {
                        ModelId::Moonshine => "Medium Streaming · English · 257 MB",
                        ModelId::Parakeet => "TDT 0.6B v2 · English · ONNX · 661 MB",
                        ModelId::Whisper => "Large v3 Turbo · English · 1.6 GB",
                    };
                    ui.label(RichText::new(description).small().color(MUTED));
                });
                ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                    let installed = models::installed(&self.controller.root.join("models"), id);
                    if self.controller.settings.selected_model == id
                        && matches!(self.controller.engine, EngineStatus::Ready)
                    {
                        ui.label(RichText::new("Selected").color(ACCENT));
                    } else if self.controller.settings.selected_model == id
                        && matches!(self.controller.engine, EngineStatus::Loading)
                    {
                        ui.spinner();
                        ui.label("Loading");
                    } else if let Some(download) =
                        self.controller.download.as_ref().filter(|d| d.id == id)
                    {
                        let progress = download.progress;
                        if ui.button("Cancel download").clicked() {
                            self.controller.cancel_download();
                        }
                        ui.add(
                            egui::ProgressBar::new(progress)
                                .desired_width(100.0)
                                .show_percentage(),
                        );
                    } else if ui
                        .add_enabled(
                            !busy && self.controller.download.is_none(),
                            egui::Button::new(if installed { "Use model" } else { "Download" })
                                .corner_radius(18),
                        )
                        .clicked()
                    {
                        if installed {
                            self.controller.load_model(id);
                        } else {
                            self.controller.download_model(id);
                        }
                    }
                });
            });
            ui.add_space(8.0);
            ui.separator();
            ui.add_space(8.0);
        }
        if let Some(download) = &self.controller.download {
            ui.label(RichText::new(&download.file).small().color(MUTED));
        }
        if let EngineStatus::Error(message) = &self.controller.engine {
            ui.colored_label(Color32::LIGHT_RED, message);
            if ui.button("Retry loading").clicked() {
                self.controller
                    .load_model(self.controller.settings.selected_model);
            }
            if ui.button("Download a fresh copy").clicked() {
                self.controller
                    .download_model(self.controller.settings.selected_model);
            }
        }
    }
    fn access(&mut self, ui: &mut egui::Ui) {
        for (microphone, label, detail, granted) in [
            (
                true,
                "Microphone",
                "Voco records only while you're dictating.",
                self.controller.permissions.microphone,
            ),
            (
                false,
                "Keyboard access",
                "Allow Voco itself in Accessibility. The Rust app has no helper.",
                self.controller.permissions.accessibility,
            ),
        ] {
            ui.horizontal(|ui| {
                ui.vertical(|ui| {
                    ui.label(RichText::new(label).size(16.0));
                    ui.label(RichText::new(detail).small().color(MUTED));
                });
                ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                    if granted {
                        ui.label(RichText::new("Allowed").color(ACCENT));
                    } else if Self::primary(ui, "Allow access").clicked() {
                        let result = if microphone {
                            platform::request_microphone()
                        } else {
                            platform::request_accessibility()
                        };
                        self.result(result);
                    }
                });
            });
            ui.separator();
        }
        ui.add_space(12.0);
        ui.label("Set Press Globe key to Do Nothing in macOS Keyboard settings. Use a different shortcut for Apple Dictation.");
        ui.add_space(8.0);
        if ui.button("Reveal Voco for Accessibility setup").clicked() {
            self.result(platform::show_app());
        }
        if ui.button("Check permissions again").clicked() {
            self.controller.refresh_permissions();
        }
        if self.controller.permissions.accessibility && !self.controller.shortcut_running {
            ui.colored_label(
                Color32::LIGHT_RED,
                "Keyboard monitoring is unavailable. Check Accessibility and restart Voco.",
            );
        }
    }
    fn home(&mut self, ui: &mut egui::Ui) {
        Self::header(
            ui,
            "Your words, at the cursor.",
            "Private dictation. Processed on your Mac.",
        );
        ui.horizontal(|ui| {
            ui.vertical(|ui| {
                ui.label(RichText::new("Hold Fn or Globe to speak.").size(22.0));
                ui.label(
                    RichText::new("Release to write. Fn + Space for a longer thought.")
                        .color(MUTED),
                );
                ui.add_space(8.0);
                ui.label(
                    RichText::new("Escape cancels. Voco never sends your message.")
                        .small()
                        .color(MUTED),
                );
            });
            ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                let (rect, _) =
                    ui.allocate_exact_size(Vec2::new(140.0, 90.0), egui::Sense::hover());
                let points = (0..80)
                    .map(|i| {
                        let x = i as f32 / 79.0;
                        let envelope = (x * std::f32::consts::PI).sin();
                        egui::pos2(
                            rect.left() + x * rect.width(),
                            rect.center().y + (x * 30.0).sin() * envelope * 27.0,
                        )
                    })
                    .collect::<Vec<_>>();
                ui.painter()
                    .add(egui::Shape::line(points, Stroke::new(2.0, ACCENT)));
            });
        });
        ui.add_space(24.0);
        ui.separator();
        ui.add_space(18.0);
        if !matches!(self.controller.engine, EngineStatus::Ready) {
            ui.label(RichText::new("Choose your speech model").size(18.0));
            ui.add_space(12.0);
            self.model_rows(ui);
        } else if !self.controller.ready() {
            ui.label(RichText::new("Allow microphone and keyboard access").size(18.0));
            ui.add_space(12.0);
            self.access(ui);
        } else {
            let summary = self
                .controller
                .settings
                .summary(chrono::Local::now().date_naive());
            ui.horizontal(|ui| {
                ui.label(RichText::new(format!("{} words", summary.words)).size(24.0));
                ui.label(
                    RichText::new(format!(
                        "{} sessions     {} day streak",
                        summary.sessions, summary.streak
                    ))
                    .color(MUTED),
                );
            });
            ui.add_space(22.0);
            ui.label(RichText::new("Try it here").size(18.0));
            ui.label(
                RichText::new("Click the field, hold Fn, and say a sentence.")
                    .small()
                    .color(MUTED),
            );
            ui.add(
                egui::TextEdit::multiline(&mut self.practice)
                    .id(egui::Id::new("practice"))
                    .desired_rows(3)
                    .desired_width(f32::INFINITY)
                    .hint_text("Your words will appear here."),
            );
            ui.add_space(18.0);
            ui.label(RichText::new("Recent transcripts").size(18.0));
            self.transcript_rows(ui, 3);
        }
        if self
            .verification
            .as_ref()
            .is_some_and(|verification| verification.stage >= 5)
            && !self.controller.ready()
        {
            ui.add(
                egui::TextEdit::multiline(&mut self.practice)
                    .id(egui::Id::new("practice"))
                    .desired_rows(3)
                    .desired_width(f32::INFINITY),
            );
        }
    }
    fn transcript_rows(&mut self, ui: &mut egui::Ui, limit: usize) {
        if self.controller.history.is_empty() {
            ui.add_space(10.0);
            ui.label(RichText::new(if self.controller.settings.keep_last_transcript { "Your finished dictations appear here until you quit." } else { "Recent transcripts are turned off. Recovery text stays available when insertion fails." }).color(MUTED));
        }
        let search = self.search.to_lowercase();
        let rows = self
            .controller
            .history
            .iter()
            .filter(|row| row.text.to_lowercase().contains(&search))
            .take(limit)
            .map(|row| (row.text.clone(), row.time.clone()))
            .collect::<Vec<_>>();
        for (text, time) in rows {
            ui.add_space(8.0);
            ui.horizontal(|ui| {
                ui.vertical(|ui| {
                    ui.label(RichText::new(time).small().color(MUTED));
                    ui.add(egui::Label::new(&text).wrap().selectable(true));
                });
                ui.with_layout(egui::Layout::right_to_left(egui::Align::TOP), |ui| {
                    if ui.button("Copy").clicked() {
                        self.copy(&text);
                    }
                });
            });
            ui.separator();
        }
    }
    fn stats(&mut self, ui: &mut egui::Ui) {
        Self::header(
            ui,
            "A little less typing.",
            "Your usage totals stay on this Mac. Audio and transcript history are never saved to disk.",
        );
        let summary = self
            .controller
            .settings
            .summary(chrono::Local::now().date_naive());
        for (label, value) in [
            ("Words dictated", summary.words.to_string()),
            ("Dictation sessions", summary.sessions.to_string()),
            (
                "Time saved",
                format!("{} min", (summary.seconds_saved / 60.0).floor()),
            ),
            ("Current streak", format!("{} days", summary.streak)),
            ("Best streak", format!("{} days", summary.best_streak)),
        ] {
            ui.horizontal(|ui| {
                ui.label(RichText::new(label).color(MUTED));
                ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                    ui.label(RichText::new(value).size(20.0));
                });
            });
            ui.separator();
        }
        ui.add_space(20.0);
        ui.label("Daily word goal");
        if ui
            .add(
                egui::Slider::new(&mut self.controller.settings.daily_goal, 100..=10000)
                    .step_by(100.0),
            )
            .changed()
        {
            self.controller.save();
        }
        ui.label("Your typing speed, used to estimate time saved");
        if ui
            .add(
                egui::Slider::new(&mut self.controller.settings.typing_wpm, 10..=200)
                    .suffix(" words/min"),
            )
            .changed()
        {
            self.controller.save();
        }
    }
    fn settings(&mut self, ui: &mut egui::Ui) {
        Self::header(
            ui,
            "Make room for your voice.",
            "Settings apply immediately.",
        );
        ui.horizontal(|ui| {
            for (tab, title) in [
                (Tab::Output, "Output"),
                (Tab::Models, "Models"),
                (Tab::Access, "Access"),
                (Tab::Dictation, "Dictation"),
            ] {
                ui.selectable_value(&mut self.tab, tab, title);
            }
        });
        ui.add_space(20.0);
        match self.tab {
            Tab::Models => self.model_rows(ui),
            Tab::Access => self.access(ui),
            Tab::Output => {
                ui.label(RichText::new("Choose how your words are cleaned up").size(18.0));
                ui.add_space(10.0);
                let before = self.controller.settings.output_mode;
                ui.add_enabled_ui(!self.controller.session.active(), |ui| {
                    ui.horizontal(|ui| {
                        for (mode, label) in [
                            (OutputMode::Fast, "Fast"),
                            (OutputMode::Balanced, "Balanced"),
                            (OutputMode::Accurate, "Accurate"),
                        ] {
                            ui.selectable_value(
                                &mut self.controller.settings.output_mode,
                                mode,
                                label,
                            );
                        }
                    });
                });
                if before != self.controller.settings.output_mode {
                    self.controller.save();
                }
                ui.add_space(12.0);
                ui.label(match self.controller.settings.output_mode {
                    OutputMode::Fast => "Keep the speech model's original transcript.",
                    OutputMode::Balanced => "Remove fillers and spoken restarts with local rules. Preserve quotes, code, links, and quantities.",
                    OutputMode::Accurate => "Uses Balanced cleanup. Apple's FoundationModels formatting is unavailable in the Rust build.",
                });
                ui.add_space(24.0);
                let mut keep = self.controller.settings.keep_last_transcript;
                if ui
                    .checkbox(&mut keep, "Keep recent transcripts until Voco quits")
                    .changed()
                {
                    self.controller.set_retention(keep);
                }
                ui.label(RichText::new("Turning this off clears recent text immediately. Failed insertion text remains available for recovery.").small().color(MUTED));
            }
            Tab::Dictation => {
                ui.label(RichText::new("Speak into the app you're using").size(18.0));
                ui.label("Hold Fn or Globe to talk. Release to finish. Press Fn + Space to start or stop continuous dictation. Press Escape to cancel.");
                ui.add_space(12.0);
                ui.label("Voco inserts the finished transcript once. Keep the original text field focused. Review your words before sending them.");
                ui.add_space(12.0);
                ui.collapsing("Your privacy", |ui| { ui.label("Speech recognition runs locally. Model downloads use the internet. No account or API key is required. Audio is held in memory only while processing. Recent transcripts are held in memory until quit."); });
            }
        }
    }
    fn recovery(&mut self, ui: &mut egui::Ui) {
        if let Session::Recovery { message, text } = &self.controller.session {
            let (message, text) = (message.clone(), text.clone());
            ui.label(RichText::new("Your dictation needs attention").size(18.0));
            if !text.is_empty() {
                ui.add(egui::Label::new(&text).wrap().selectable(true));
            }
            ui.label(RichText::new(message).color(MUTED));
            ui.horizontal(|ui| {
                if !text.is_empty() && Self::primary(ui, "Copy your words").clicked() {
                    self.controller.copy_recovery();
                }
                if ui.button("Dismiss").clicked() {
                    self.controller.cancel();
                }
            });
            ui.separator();
        }
    }
    fn verify(&mut self, ctx: &egui::Context) {
        let Some(verification) = &mut self.verification else {
            return;
        };
        let pages = [Page::Home, Page::Transcripts, Page::Stats, Page::Settings];
        if verification.started.elapsed() > Duration::from_secs(30) {
            eprintln!("UI verification timed out");
            std::process::exit(1);
        }
        let screenshots = ctx.input(|input| {
            input
                .events
                .iter()
                .filter_map(|event| {
                    if let egui::Event::Screenshot { image, .. } = event {
                        Some(image.clone())
                    } else {
                        None
                    }
                })
                .collect::<Vec<_>>()
        });
        for image in screenshots {
            let path = verification
                .directory
                .join(format!("{}.png", verification.captures));
            let bytes = image
                .pixels
                .iter()
                .flat_map(|pixel| pixel.to_array())
                .collect::<Vec<_>>();
            if let Err(error) = image::save_buffer(
                path,
                &bytes,
                image.width() as u32,
                image.height() as u32,
                image::ColorType::Rgba8,
            ) {
                eprintln!("Screenshot failed: {error}");
                std::process::exit(1);
            }
            verification.captures += 1;
        }
        let elapsed = verification.started.elapsed().as_millis();
        if verification.stage < 4 && elapsed > 600 * (verification.stage as u128 + 1) {
            self.page = pages[verification.stage];
            self.visible = true;
            ctx.send_viewport_cmd(egui::ViewportCommand::Visible(true));
            ctx.send_viewport_cmd(egui::ViewportCommand::Screenshot(Default::default()));
            verification.stage += 1;
        }
        if verification.captures == 4 && verification.stage == 4 {
            self.page = Page::Home;
            self.practice = "Before 😀 after".into();
            ctx.memory_mut(|memory| memory.request_focus(egui::Id::new("practice")));
            platform::activate_dashboard();
            ctx.send_viewport_cmd(egui::ViewportCommand::Focus);
            verification.stage = 5;
        } else if verification.stage == 5 {
            if let Some(mut state) =
                egui::text_edit::TextEditState::load(ctx, egui::Id::new("practice"))
            {
                state
                    .cursor
                    .set_char_range(Some(egui::text::CCursorRange::two(
                        egui::text::CCursor::new(7),
                        egui::text::CCursor::new(8),
                    )));
                state.store(ctx, egui::Id::new("practice"));
                verification.practice_ready = Some(Instant::now());
                verification.stage = 6;
            }
        } else if verification.stage == 6
            && verification
                .practice_ready
                .is_some_and(|at| at.elapsed() >= Duration::from_millis(500))
        {
            let result = practice_snapshot(ctx, &self.practice, self.ime_composing)
                .ok_or_else(|| anyhow::anyhow!("The practice field is not focused"))
                .and_then(|target| target.replace(&target, "Rust"));
            match result {
                Ok((replacement, caret)) => {
                    apply_practice_update(ctx, &mut self.practice, replacement, caret);
                    if self.practice != "Before Rust after" {
                        eprintln!("Practice insertion produced an incorrect value");
                        std::process::exit(1);
                    }
                    verification.practice_verified = true;
                    verification.stage = 7;
                }
                Err(error) => {
                    eprintln!("Practice insertion failed: {error:#}");
                    std::process::exit(1);
                }
            }
        }
        if verification.practice_verified {
            let report = serde_json::json!({ "runtime": "rust", "ui": "egui", "pagesRendered": 4, "screenshots": 4,
                "trayCreated": true, "practiceInsertion": verification.practice_verified, "microphone": self.controller.permissions.microphone, "accessibility": self.controller.permissions.accessibility,
                "shortcut": self.controller.shortcut_running, "status": self.controller.status(), "transcriptPersistence": false });
            if let Err(error) = std::fs::write(
                verification.directory.join("report.json"),
                serde_json::to_vec_pretty(&report).unwrap_or_default(),
            ) {
                eprintln!("Report failed: {error}");
                std::process::exit(1);
            }
            self.quitting = true;
            ctx.send_viewport_cmd(egui::ViewportCommand::Close);
        }
    }
}

impl eframe::App for VocoApp {
    fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
        ctx.input(|input| {
            for event in &input.events {
                match event {
                    egui::Event::Ime(egui::ImeEvent::Preedit(text)) => {
                        self.ime_composing = !text.is_empty()
                    }
                    egui::Event::Ime(egui::ImeEvent::Commit(_) | egui::ImeEvent::Disabled) => {
                        self.ime_composing = false
                    }
                    _ => {}
                }
            }
        });
        self.controller.practice_snapshot = if self.visible && self.page == Page::Home {
            practice_snapshot(ctx, &self.practice, self.ime_composing)
        } else {
            None
        };
        self.controller.tick();
        if let Some((replacement, caret)) = self.controller.practice_update.take() {
            apply_practice_update(ctx, &mut self.practice, replacement, caret);
        }
        if std::fs::remove_file(self.controller.root.join("show-dashboard")).is_ok() {
            self.show(ctx, Page::Home);
        }
        while let Ok(event) = MenuEvent::receiver().try_recv() {
            match event.id.as_ref() {
                "home" => self.show(ctx, Page::Home),
                "transcripts" => self.show(ctx, Page::Transcripts),
                "stats" => self.show(ctx, Page::Stats),
                "settings" => self.show(ctx, Page::Settings),
                "copy" => {
                    if let Some(row) = self.controller.history.front() {
                        let text = row.text.clone();
                        self.copy(&text);
                    }
                }
                "quit" => {
                    self.quitting = true;
                    ctx.send_viewport_cmd(egui::ViewportCommand::Close);
                }
                _ => {}
            }
        }
        if self.controller.show_dashboard {
            self.controller.show_dashboard = false;
            self.show(ctx, Page::Home);
        }
        if ctx.input(|input| input.viewport().close_requested()) && !self.quitting {
            ctx.send_viewport_cmd(egui::ViewportCommand::CancelClose);
            ctx.send_viewport_cmd(egui::ViewportCommand::Visible(false));
            self.visible = false;
        }
        self.copy_menu
            .set_enabled(!self.controller.history.is_empty());
        let _ = self
            .tray
            .set_tooltip(Some(format!("Voco · {}", self.controller.status())));
        self.overlay.update(
            self.controller.status(),
            self.controller.level(),
            self.controller.session.active(),
        );
        if self.visible {
            egui::SidePanel::left("navigation")
                .exact_width(154.0)
                .show(ctx, |ui| {
                    ui.add_space(24.0);
                    ui.label(RichText::new("voco.").size(30.0).color(TEXT));
                    ui.add_space(30.0);
                    for (page, title) in [
                        (Page::Home, "Home"),
                        (Page::Transcripts, "Transcripts"),
                        (Page::Stats, "Stats"),
                    ] {
                        if ui
                            .add_sized(
                                [126.0, 38.0],
                                egui::Button::new(title)
                                    .selected(self.page == page)
                                    .corner_radius(10),
                            )
                            .clicked()
                        {
                            self.page = page;
                        }
                    }
                    ui.with_layout(egui::Layout::bottom_up(egui::Align::LEFT), |ui| {
                        ui.add_space(20.0);
                        if ui
                            .add_sized(
                                [126.0, 38.0],
                                egui::Button::new("Settings")
                                    .selected(self.page == Page::Settings)
                                    .corner_radius(10),
                            )
                            .clicked()
                        {
                            self.page = Page::Settings;
                        }
                        ui.label(RichText::new("On your Mac.").small().color(MUTED));
                    });
                });
            egui::TopBottomPanel::bottom("live_status").show(ctx, |ui| {
                ui.add_space(8.0);
                ui.horizontal(|ui| {
                    ui.colored_label(ACCENT, self.controller.status());
                    if matches!(
                        self.controller.session,
                        Session::Listening { .. } | Session::Finishing | Session::Armed
                    ) && ui.button("Cancel · Esc").clicked()
                    {
                        self.controller.cancel();
                    }
                    if self
                        .copied_until
                        .is_some_and(|until| Instant::now() < until)
                    {
                        ui.label("Copied");
                    }
                });
                if !self.controller.notice.is_empty() {
                    ui.label(RichText::new(&self.controller.notice).color(MUTED).small());
                }
                ui.add_space(8.0);
            });
            egui::CentralPanel::default()
                .frame(egui::Frame::new().fill(BACKGROUND).inner_margin(28.0))
                .show(ctx, |ui| {
                    egui::ScrollArea::vertical().show(ui, |ui| {
                        self.recovery(ui);
                        match self.page {
                            Page::Home => self.home(ui),
                            Page::Transcripts => {
                                Self::header(
                                    ui,
                                    "The words you kept.",
                                    "Recent dictations stay here until you quit Voco.",
                                );
                                ui.add(
                                    egui::TextEdit::singleline(&mut self.search)
                                        .hint_text("Search transcripts")
                                        .desired_width(f32::INFINITY),
                                );
                                self.transcript_rows(ui, 50);
                            }
                            Page::Stats => self.stats(ui),
                            Page::Settings => self.settings(ui),
                        }
                    });
                });
        }
        self.verify(ctx);
        ctx.request_repaint_after(Duration::from_millis(
            if self.controller.session.active() || self.verification.is_some() {
                30
            } else {
                100
            },
        ));
    }
}

fn apply_practice_update(
    ctx: &egui::Context,
    practice: &mut String,
    replacement: String,
    caret: usize,
) {
    *practice = replacement;
    if let Some(mut state) = egui::text_edit::TextEditState::load(ctx, egui::Id::new("practice")) {
        state
            .cursor
            .set_char_range(Some(egui::text::CCursorRange::one(
                egui::text::CCursor::new(caret),
            )));
        state.store(ctx, egui::Id::new("practice"));
    }
}

fn practice_snapshot(
    ctx: &egui::Context,
    value: &str,
    composing: bool,
) -> Option<crate::practice::PracticeTarget> {
    let id = egui::Id::new("practice");
    if composing
        || ctx.input(|input| {
            input.pointer.any_down()
                || input.events.iter().any(|event| {
                    matches!(
                        event,
                        egui::Event::Text(_)
                            | egui::Event::Paste(_)
                            | egui::Event::Cut
                            | egui::Event::Key { pressed: true, .. }
                            | egui::Event::PointerButton { .. }
                            | egui::Event::Ime(_)
                    )
                })
        })
    {
        return None;
    }
    if ctx.memory(|memory| memory.focused()) != Some(id) {
        return None;
    }
    let state = egui::text_edit::TextEditState::load(ctx, id)?;
    let selection = state.cursor.char_range()?.as_sorted_char_range();
    crate::practice::PracticeTarget::capture(value, selection).ok()
}
