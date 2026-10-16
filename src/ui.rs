use crate::overlay::Overlay;
use crate::{
    controller::{Controller, EngineStatus},
    domain::{ModelId, OutputMode, Session},
    models, platform,
};
use anyhow::Result;
use gpui::{prelude::*, *};
use gpui_component::{
    Disableable, Root, Theme, ThemeMode,
    button::{Button, ButtonVariants},
    input::{Input, InputState},
};
use std::{
    path::PathBuf,
    time::{Duration, Instant},
};
use tray_icon::{
    TrayIcon, TrayIconBuilder,
    menu::{Menu, MenuEvent, MenuItem, PredefinedMenuItem, Submenu},
};

const BG: u32 = 0x0a0a0a;
const TEXT: u32 = 0xf2f0ec;
const MUTED: u32 = 0x929497;
const LINE: u32 = 0x282828;
const ORANGE: u32 = 0xff742f;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Page {
    Home,
    Transcripts,
    Stats,
    Settings,
}
#[derive(Clone, Copy, PartialEq, Eq)]
enum SettingsTab {
    Output,
    Models,
    Access,
    Dictation,
}

pub struct VocoApp {
    controller: Controller,
    page: Page,
    tab: SettingsTab,
    settings_focus: FocusHandle,
    tray: TrayIcon,
    _application_menu: Menu,
    copy_menu: MenuItem,
    overlay: Overlay,
    visible: bool,
    practice: Entity<InputState>,
    search: Entity<InputState>,
    copied_until: Option<Instant>,
    verification: Option<Verification>,
}
struct Verification {
    directory: PathBuf,
    started: Instant,
    stage: usize,
    practice_verified: bool,
    close_verified: bool,
    stage_started: Instant,
    capture: Option<std::sync::mpsc::Receiver<std::result::Result<(), String>>>,
}

fn literal_text(id: SharedString, value: &str, window: &mut Window, cx: &mut App) -> Input {
    let state = window.use_keyed_state(id, cx, |window, cx| {
        InputState::new(window, cx).auto_grow(1, 12)
    });
    if state.read(cx).value().as_ref() != value {
        state.update(cx, |input, cx| {
            input.set_value(value.to_owned(), window, cx)
        });
    }
    Input::new(&state)
        .appearance(false)
        .disabled(true)
        .p(px(0.))
        .text_size(px(13.))
        .text_color(rgb(TEXT))
}

struct Assets;
impl AssetSource for Assets {
    fn load(&self, path: &str) -> Result<Option<std::borrow::Cow<'static, [u8]>>> {
        let bytes: &'static [u8] = match path {
            "home" => include_bytes!("../Resources/Icons/home.svg"),
            "transcripts" => include_bytes!("../Resources/Icons/transcripts.svg"),
            "stats" => include_bytes!("../Resources/Icons/stats.svg"),
            "settings" => include_bytes!("../Resources/Icons/settings.svg"),
            "globe" => include_bytes!("../Resources/Icons/globe.svg"),
            _ => return Ok(None),
        };
        Ok(Some(std::borrow::Cow::Borrowed(bytes)))
    }
    fn list(&self, _: &str) -> Result<Vec<SharedString>> {
        Ok(vec![])
    }
}

pub fn run(root: PathBuf, show: bool, verification: Option<PathBuf>) -> Result<()> {
    let controller = Controller::new(root)?;
    Application::new().with_assets(Assets).run(move |cx| {
        gpui_component::init(cx);
        Theme::change(ThemeMode::Dark, None, cx);
        let theme = Theme::global_mut(cx);
        theme.font_family = "Manrope".into();
        theme.font_size = px(13.);
        theme.colors.background = rgb(BG).into();
        theme.colors.foreground = rgb(TEXT).into();
        theme.colors.input = rgb(0x141414).into();
        theme.colors.border = rgb(LINE).into();
        theme.colors.ring = rgb(ORANGE).into();
        theme.colors.primary = rgb(TEXT).into();
        theme.colors.primary_foreground = rgb(BG).into();
        cx.text_system()
            .add_fonts(vec![
                std::borrow::Cow::Borrowed(include_bytes!(
                    "../Resources/Fonts/Manrope-Regular.ttf"
                )),
                std::borrow::Cow::Borrowed(include_bytes!("../Resources/Fonts/Manrope-Medium.ttf")),
                std::borrow::Cow::Borrowed(include_bytes!(
                    "../Resources/Fonts/Manrope-SemiBold.ttf"
                )),
            ])
            .expect("bundled Manrope font");
        let bounds = Bounds::centered(None, size(px(1080.), px(800.)), cx);
        cx.open_window(
            WindowOptions {
                window_bounds: Some(WindowBounds::Windowed(bounds)),
                titlebar: Some(TitlebarOptions {
                    title: Some("Voco".into()),
                    appears_transparent: true,
                    ..Default::default()
                }),
                window_min_size: Some(size(px(820.), px(640.))),
                show,
                focus: show,
                app_id: Some("org.vocoapp.Voco".into()),
                ..Default::default()
            },
            move |window, cx| {
                let view = cx.new(|cx| {
                    VocoApp::new(controller, show, verification, window, cx)
                        .expect("native dashboard")
                });
                let weak = view.downgrade();
                window.on_window_should_close(cx, move |_, cx| {
                    weak.update(cx, |app, cx| {
                        app.visible = false;
                        dashboard_visibility(false);
                        cx.notify();
                    })
                    .ok();
                    false
                });
                cx.new(|cx| Root::new(view, window, cx))
            },
        )
        .expect("Voco window");
        if show {
            cx.activate(true);
        }
    });
    Ok(())
}

fn dashboard_visibility(show: bool) {
    if let Some(main) = objc2::MainThreadMarker::new() {
        let app = objc2_app_kit::NSApplication::sharedApplication(main);
        for window in app
            .windows()
            .iter()
            .filter(|w| w.title().to_string() == "Voco")
        {
            if show {
                window.makeKeyAndOrderFront(None);
            } else {
                window.orderOut(None);
            }
        }
    }
    if show {
        platform::activate_dashboard();
    }
}

fn request_dashboard_close() {
    unsafe extern "C" {
        static _dispatch_main_q: std::ffi::c_void;
        fn dispatch_async_f(
            queue: *const std::ffi::c_void,
            context: *mut std::ffi::c_void,
            work: extern "C" fn(*mut std::ffi::c_void),
        );
    }
    extern "C" fn close(_: *mut std::ffi::c_void) {
        if let Some(main) = objc2::MainThreadMarker::new() {
            for native in objc2_app_kit::NSApplication::sharedApplication(main)
                .windows()
                .iter()
                .filter(|w| w.title().to_string() == "Voco")
            {
                native.performClose(None);
            }
        }
    }
    unsafe {
        dispatch_async_f(&raw const _dispatch_main_q, std::ptr::null_mut(), close);
    }
}

impl VocoApp {
    fn new(
        controller: Controller,
        show: bool,
        verification: Option<PathBuf>,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) -> Result<Self> {
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
        let overlay = Overlay::new(cx)?;
        let mut controller = controller;
        if verification.is_some() {
            controller.history.push_back(crate::controller::Transcript { time: "Verify 09:41".into(), text: "Verification example. A thought can arrive in its own time, with room to breathe.".into() });
            controller.history.push_back(crate::controller::Transcript { time: "Verify 09:40".into(), text: "Verification literal. &copy; <tag> **words** 😀 café\n    Four leading spaces stay exactly as dictated.\nA second line, without changing your words.".into() });
        }
        let practice = cx.new(|cx| {
            InputState::new(window, cx)
                .multi_line(true)
                .placeholder("Click here, hold Fn, and let your thoughts flow…")
        });
        let search = cx.new(|cx| InputState::new(window, cx).placeholder("Search your words…"));
        cx.spawn_in(window, async move |this, cx| {
            loop {
                cx.background_executor()
                    .timer(Duration::from_millis(60))
                    .await;
                if this
                    .update_in(cx, |app, window, cx| app.tick(window, cx))
                    .is_err()
                {
                    break;
                }
            }
        })
        .detach();
        Ok(Self {
            controller,
            page: Page::Home,
            tab: SettingsTab::Output,
            settings_focus: cx.focus_handle(),
            tray,
            _application_menu: application_menu,
            copy_menu,
            overlay,
            visible: show,
            practice,
            search,
            copied_until: None,
            verification: verification.map(|directory| Verification {
                directory,
                started: Instant::now(),
                stage: 0,
                practice_verified: false,
                close_verified: false,
                stage_started: Instant::now(),
                capture: None,
            }),
        })
    }
    fn show(&mut self, page: Page, window: &mut Window, cx: &mut Context<Self>) {
        self.page = page;
        self.visible = true;
        dashboard_visibility(true);
        window.activate_window();
        cx.notify();
    }
    fn copy(&mut self, text: &str) {
        match platform::copy_text(text) {
            Ok(()) => self.copied_until = Some(Instant::now() + Duration::from_secs(2)),
            Err(error) => self.controller.notice = format!("Could not copy. {error}"),
        }
    }
    fn result(&mut self, result: Result<()>) {
        if let Err(error) = result {
            self.controller.notice = error.to_string();
        }
    }
    fn practice_target(
        &mut self,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) -> Option<crate::practice::PracticeTarget> {
        if !self.visible
            || self.page != Page::Home
            || !self.practice.focus_handle(cx).is_focused(window)
        {
            return None;
        }
        self.practice.update(cx, |input, cx| {
            if input.marked_text_range(window, cx).is_some() {
                return None;
            }
            let selection = input.selected_text_range(false, window, cx)?.range;
            let value = input.value();
            let to_chars = |offset| {
                let mut units = 0;
                value
                    .chars()
                    .take_while(|c| {
                        units += c.len_utf16();
                        units <= offset
                    })
                    .count()
            };
            crate::practice::PracticeTarget::capture(
                &value,
                to_chars(selection.start)..to_chars(selection.end),
            )
            .ok()
        })
    }
    fn apply_practice_update(
        &mut self,
        value: String,
        caret: usize,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        self.practice.update(cx, |input, cx| {
            let prefix: String = value.chars().take(caret).collect();
            let line = prefix.matches('\n').count() as u32;
            let character = prefix.rsplit('\n').next().unwrap_or("").chars().count() as u32;
            input.set_value(value, window, cx);
            input.set_cursor_position(
                gpui_component::input::Position { line, character },
                window,
                cx,
            );
        });
    }
    fn tick(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        self.controller.practice_snapshot = self.practice_target(window, cx);
        self.controller.tick();
        if let Some((value, caret)) = self.controller.practice_update.take() {
            self.apply_practice_update(value, caret, window, cx);
        }
        if std::fs::remove_file(self.controller.root.join("show-dashboard")).is_ok() {
            self.show(Page::Home, window, cx);
        }
        while let Ok(event) = MenuEvent::receiver().try_recv() {
            match event.id.as_ref() {
                "home" => self.show(Page::Home, window, cx),
                "transcripts" => self.show(Page::Transcripts, window, cx),
                "stats" => self.show(Page::Stats, window, cx),
                "settings" => self.show(Page::Settings, window, cx),
                "copy" => {
                    if let Some(row) = self.controller.history.front() {
                        let text = row.text.clone();
                        self.copy(&text);
                    }
                }
                "quit" => cx.quit(),
                _ => {}
            }
        }
        if self.controller.show_dashboard {
            self.controller.show_dashboard = false;
            self.show(Page::Home, window, cx);
        }
        self.copy_menu
            .set_enabled(!self.controller.history.is_empty());
        let _ = self
            .tray
            .set_tooltip(Some(format!("Voco · {}", self.controller.status())));
        if let Some(stage @ (9 | 10)) = self
            .verification
            .as_ref()
            .map(|verification| verification.stage)
        {
            self.overlay.update(
                if stage == 9 {
                    "Listening"
                } else {
                    "Transcribing"
                },
                if stage == 9 { 0.42 } else { 0. },
                true,
                cx,
            );
        } else {
            self.overlay.update(
                self.controller.status(),
                self.controller.level(),
                self.controller.session.active(),
                cx,
            );
        }
        self.verify(window, cx);
        if self.visible {
            cx.notify();
        }
    }
    fn button(
        &self,
        id: impl Into<ElementId>,
        label: impl Into<SharedString>,
        primary: bool,
        cx: &mut Context<Self>,
        action: impl Fn(&mut Self, &mut Window, &mut Context<Self>) + 'static,
    ) -> Button {
        Button::new(id)
            .child(
                div()
                    .text_color(rgb(if primary { BG } else { TEXT }))
                    .child(label.into()),
            )
            .when(primary, |button| button.primary())
            .rounded(px(999.))
            .h(px(34.))
            .px(px(15.))
            .text_size(px(12.))
            .text_color(rgb(if primary { BG } else { TEXT }))
            .on_click(cx.listener(move |app, _, window, cx| {
                action(app, window, cx);
                cx.notify();
            }))
    }
    fn heading(&self, title: &str, detail: &str) -> Div {
        div()
            .flex()
            .flex_col()
            .gap(px(8.))
            .mb(px(28.))
            .child(
                div()
                    .text_size(px(34.))
                    .font_weight(FontWeight::MEDIUM)
                    .child(title.to_owned()),
            )
            .child(
                div()
                    .text_size(px(13.))
                    .text_color(rgb(MUTED))
                    .child(detail.to_owned()),
            )
    }
    fn sidebar(&self, cx: &mut Context<Self>) -> Div {
        let mut nav = div().flex().flex_col().gap(px(6.)).mt(px(34.));
        for (page, icon, label) in [
            (Page::Home, "home", "Home"),
            (Page::Transcripts, "transcripts", "Transcripts"),
            (Page::Stats, "stats", "Statistics"),
        ] {
            nav = nav.child(self.nav(page, icon, label, cx));
        }
        div()
            .w(px(174.))
            .flex_shrink_0()
            .h_full()
            .border_r_1()
            .border_color(rgb(LINE))
            .px(px(18.))
            .pt(px(28.))
            .pb(px(20.))
            .flex()
            .flex_col()
            .child(
                div()
                    .px(px(10.))
                    .flex()
                    .items_baseline()
                    .child(
                        div()
                            .text_size(px(31.))
                            .font_weight(FontWeight::SEMIBOLD)
                            .child("voco"),
                    )
                    .child(div().text_color(rgb(ORANGE)).text_size(px(32.)).child(".")),
            )
            .child(nav)
            .child(div().flex_1())
            .child(
                div()
                    .px(px(10.))
                    .mb(px(18.))
                    .text_size(px(10.))
                    .text_color(rgb(MUTED))
                    .child("Made for your Mac."),
            )
            .child(self.nav(Page::Settings, "settings", "Settings", cx))
    }
    fn nav(
        &self,
        page: Page,
        icon: &'static str,
        label: &'static str,
        cx: &mut Context<Self>,
    ) -> Button {
        Button::new(SharedString::from(format!("nav-{page:?}")))
            .ghost()
            .rounded(px(10.))
            .w_full()
            .h(px(40.))
            .justify_start()
            .gap(px(11.))
            .bg(rgb(if self.page == page { 0x202020 } else { BG }))
            .text_color(rgb(if self.page == page { TEXT } else { MUTED }))
            .on_click(cx.listener(move |app, _, _, cx| {
                app.page = page;
                cx.notify();
            }))
            .child(svg().path(icon).size(px(17.)).text_color(rgb(TEXT)))
            .child(label)
    }
    fn artwork(&self) -> Div {
        let mut sculpture = div()
            .w(px(234.))
            .h(px(150.))
            .flex()
            .flex_col()
            .justify_center()
            .overflow_hidden()
            .font_family("Menlo")
            .text_size(px(7.))
            .line_height(px(6.));
        for row in 0..24 {
            let mut line = String::new();
            for col in 0..48 {
                let x = col as f32 / 47.;
                let y = row as f32;
                let center = 12. + (x * 6.8 - 1.2).sin() * 6.;
                let width = 2. + (x * std::f32::consts::PI).sin() * 4.;
                let delta = (y - center).abs();
                let glyph = if delta < width {
                    if (col + row) % 5 == 0 {
                        ':'
                    } else if delta > width - 1.5 {
                        '.'
                    } else {
                        '+'
                    }
                } else {
                    ' '
                };
                line.push(glyph);
            }
            sculpture = sculpture.child(
                div()
                    .text_color(rgb(if row < 12 { ORANGE } else { 0xc95524 }))
                    .whitespace_nowrap()
                    .child(line),
            );
        }
        sculpture
    }
    fn metrics(&self) -> Div {
        let summary = self
            .controller
            .settings
            .summary(chrono::Local::now().date_naive());
        let mut row = div()
            .flex()
            .w_full()
            .py(px(24.))
            .border_b_1()
            .border_color(rgb(LINE));
        for (index, value, label) in [
            (0, summary.words.to_string(), "Words dictated"),
            (
                1,
                format!("{} min", (summary.seconds_saved / 60.).floor()),
                "Time given back",
            ),
            (2, format!("{} days", summary.streak), "Current streak"),
        ] {
            row = row.child(
                div()
                    .flex_1()
                    .px(px(if index == 0 { 0. } else { 24. }))
                    .when(index > 0, |s| s.border_l_1().border_color(rgb(LINE)))
                    .child(div().text_size(px(28.)).child(value))
                    .child(
                        div()
                            .mt(px(5.))
                            .text_size(px(11.))
                            .text_color(rgb(MUTED))
                            .child(label),
                    ),
            );
        }
        row
    }
    fn home(&self, window: &mut Window, cx: &mut Context<Self>) -> Div {
        let ready = self.controller.ready();
        let mut page = div()
            .flex()
            .flex_col()
            .child(self.heading(
                "Room for your next thought.",
                "Less between what you think and what you write.",
            ))
            .child(
                div()
                    .flex()
                    .justify_between()
                    .items_center()
                    .border_y_1()
                    .border_color(rgb(LINE))
                    .py(px(18.))
                    .child(
                        div()
                            .flex()
                            .flex_col()
                            .gap(px(12.))
                            .child(
                                div()
                                    .text_size(px(22.))
                                    .child("Speak naturally. Write effortlessly."),
                            )
                            .child(
                                div()
                                    .flex()
                                    .items_center()
                                    .gap(px(9.))
                                    .child(
                                        div()
                                            .bg(rgb(0x202020))
                                            .border_1()
                                            .border_b_2()
                                            .border_color(rgb(0x414141))
                                            .rounded(px(7.))
                                            .px(px(12.))
                                            .py(px(6.))
                                            .child(
                                                div()
                                                    .flex()
                                                    .items_center()
                                                    .gap(px(5.))
                                                    .child("fn /")
                                                    .child(
                                                        svg()
                                                            .path("globe")
                                                            .size(px(13.))
                                                            .text_color(rgb(TEXT)),
                                                    ),
                                            ),
                                    )
                                    .child(
                                        div()
                                            .text_color(rgb(MUTED))
                                            .child("Hold to speak. Release to write."),
                                    ),
                            )
                            .child(
                                div()
                                    .text_size(px(11.))
                                    .text_color(rgb(MUTED))
                                    .child("Fn + Space for a longer thought · Esc to cancel"),
                            ),
                    )
                    .when(window.bounds().size.width >= px(960.), |s| {
                        s.child(self.artwork())
                    }),
            )
            .child(self.metrics());
        if !ready {
            let model_ready = matches!(self.controller.engine, EngineStatus::Ready);
            page = page.child(
                div()
                    .flex()
                    .items_center()
                    .justify_between()
                    .gap(px(20.))
                    .py(px(18.))
                    .border_b_1()
                    .border_color(rgb(LINE))
                    .child(
                        div()
                            .flex()
                            .flex_col()
                            .gap(px(5.))
                            .child(if model_ready {
                                "One last thing. Make yourself heard."
                            } else {
                                "Your private voice workspace starts here."
                            })
                            .child(div().text_size(px(12.)).text_color(rgb(MUTED)).child(
                                if model_ready {
                                    "Allow microphone and keyboard access to begin."
                                } else {
                                    "Choose a local speech model. No account. No cloud."
                                },
                            )),
                    )
                    .child(self.button(
                        "finish-setup",
                        if model_ready {
                            "Allow access ↗"
                        } else {
                            "Choose a model ↗"
                        },
                        true,
                        cx,
                        move |app, _, _| {
                            app.page = Page::Settings;
                            app.tab = if model_ready {
                                SettingsTab::Access
                            } else {
                                SettingsTab::Models
                            };
                        },
                    )),
            );
        }
        page.child(
            div()
                .flex()
                .items_center()
                .justify_between()
                .mt(px(22.))
                .mb(px(10.))
                .child("A space to try your voice")
                .child(
                    div()
                        .text_size(px(11.))
                        .text_color(rgb(MUTED))
                        .child("Click below, then hold Fn"),
                ),
        )
        .child(
            Input::new(&self.practice)
                .h(px(86.))
                .rounded(px(12.))
                .bg(rgb(0x141414)),
        )
        .child(
            div()
                .mt(px(24.))
                .mb(px(7.))
                .flex()
                .justify_between()
                .items_center()
                .child("Recent words")
                .child(
                    self.button("all-transcripts", "View all ↗", false, cx, |app, _, _| {
                        app.page = Page::Transcripts
                    }),
                ),
        )
        .child(self.transcripts(3, window, cx))
    }
    fn transcript_count(&self, cx: &App) -> usize {
        let search = self.search.read(cx).value().to_lowercase();
        self.controller
            .history
            .iter()
            .filter(|row| row.text.to_lowercase().contains(&search))
            .count()
    }
    fn transcripts(&self, limit: usize, window: &mut Window, cx: &mut Context<Self>) -> Div {
        let search = self.search.read(cx).value().to_lowercase();
        let rows = self
            .controller
            .history
            .iter()
            .filter(|row| {
                self.page != Page::Transcripts || row.text.to_lowercase().contains(&search)
            })
            .take(limit)
            .collect::<Vec<_>>();
        let mut list = div().flex().flex_col();
        if rows.is_empty() {
            list = list.child(
                div()
                    .py(px(24.))
                    .text_color(rgb(MUTED))
                    .text_size(px(12.))
                    .child(if !self.controller.settings.keep_last_transcript {
                        "Recent words are off. Enable them in Settings → Output."
                    } else if !search.is_empty() && self.page == Page::Transcripts {
                        "No words match your search."
                    } else {
                        "Your next thought belongs here. Finished dictations stay until you quit."
                    }),
            );
        }
        for (index, row) in rows.iter().enumerate() {
            let text = row.text.clone();
            list = list.child(
                div()
                    .flex()
                    .items_start()
                    .gap(px(16.))
                    .py(px(17.))
                    .border_b_1()
                    .border_color(rgb(LINE))
                    .child(
                        div()
                            .w(px(64.))
                            .flex_shrink_0()
                            .pt(px(4.))
                            .text_size(px(10.))
                            .text_color(rgb(MUTED))
                            .child(row.time.clone()),
                    )
                    .child(
                        div()
                            .flex_1()
                            .text_size(px(13.))
                            .line_height(px(22.))
                            .child(literal_text(
                                SharedString::from(format!("transcript-text-{index}")),
                                &row.text,
                                window,
                                cx,
                            )),
                    )
                    .child(self.button(
                        SharedString::from(format!("copy-{index}")),
                        "Copy",
                        false,
                        cx,
                        move |app, _, _| app.copy(&text),
                    )),
            );
        }
        list
    }
    fn models(&self, cx: &mut Context<Self>) -> Div {
        let mut rows = div().flex().flex_col();
        for id in ModelId::ALL {
            let installed = models::installed(&self.controller.root.join("models"), id);
            let selected = self.controller.settings.selected_model == id;
            let download = self.controller.download.as_ref().filter(|d| d.id == id);
            let label = if download.is_some() {
                "Cancel download"
            } else if selected && matches!(self.controller.engine, EngineStatus::Loading) {
                "Loading…"
            } else if selected && matches!(self.controller.engine, EngineStatus::Ready) {
                "Selected ✓"
            } else if installed {
                "Use model"
            } else {
                "Download ↓"
            };
            let detail = match id {
                ModelId::Moonshine => "Medium Streaming · English · 257 MB",
                ModelId::Parakeet => "TDT 0.6B v2 · English · 661 MB",
                ModelId::Whisper => "Large v3 Turbo · English · 1.6 GB",
            };
            let mut row = div()
                .flex()
                .flex_col()
                .py(px(24.))
                .border_b_1()
                .border_color(rgb(LINE))
                .gap(px(12.))
                .child(
                    div()
                        .flex()
                        .items_center()
                        .justify_between()
                        .gap(px(16.))
                        .child(
                            div()
                                .flex()
                                .flex_col()
                                .gap(px(6.))
                                .child(div().text_size(px(19.)).child(id.label()))
                                .child(
                                    div()
                                        .text_size(px(12.))
                                        .text_color(rgb(MUTED))
                                        .child(detail),
                                ),
                        )
                        .child(
                            self.button(
                                SharedString::from(format!("model-{id:?}")),
                                label,
                                !installed,
                                cx,
                                move |app, _, _| {
                                    if app.controller.download.as_ref().is_some_and(|d| d.id == id)
                                    {
                                        app.controller.cancel_download();
                                    } else if !app.controller.session.active()
                                        && app.controller.download.is_none()
                                    {
                                        if installed {
                                            app.controller.load_model(id);
                                        } else {
                                            app.controller.download_model(id);
                                        }
                                    }
                                },
                            )
                            .disabled(
                                (self.controller.session.active()
                                    || self.controller.download.is_some())
                                    && download.is_none(),
                            ),
                        ),
                );
            if let Some(download) = download {
                row = row
                    .child(
                        div()
                            .text_size(px(11.))
                            .text_color(rgb(ORANGE))
                            .child(format!(
                                "{:.0}% · {}",
                                download.progress * 100.,
                                download.file
                            )),
                    )
                    .child(
                        div().h(px(3.)).rounded_full().bg(rgb(LINE)).child(
                            div()
                                .h_full()
                                .w(relative(download.progress.clamp(0., 1.)))
                                .bg(rgb(ORANGE)),
                        ),
                    );
            }
            rows = rows.child(row);
        }
        if let EngineStatus::Error(message) = &self.controller.engine {
            rows = rows
                .child(
                    div()
                        .py(px(16.))
                        .text_color(rgb(0xff9d9d))
                        .child(message.clone()),
                )
                .child(
                    div()
                        .flex()
                        .gap(px(10.))
                        .child(
                            self.button("retry", "Retry loading", true, cx, |app, _, _| {
                                app.controller
                                    .load_model(app.controller.settings.selected_model)
                            }),
                        )
                        .child(self.button(
                            "redownload",
                            "Download a fresh copy",
                            false,
                            cx,
                            |app, _, _| {
                                if !app.controller.session.active()
                                    && app.controller.download.is_none()
                                {
                                    app.controller
                                        .download_model(app.controller.settings.selected_model);
                                }
                            },
                        )),
                );
        }
        rows
    }
    fn access(&self, cx: &mut Context<Self>) -> Div {
        let mut panel = div().flex().flex_col();
        for (mic, title, detail, granted) in [
            (
                true,
                "Microphone",
                "Only listening when you choose to speak.",
                self.controller.permissions.microphone,
            ),
            (
                false,
                "Keyboard access",
                "Insert your words in the app you're using.",
                self.controller.permissions.accessibility,
            ),
        ] {
            panel = panel.child(
                div()
                    .flex()
                    .items_center()
                    .justify_between()
                    .py(px(24.))
                    .border_b_1()
                    .border_color(rgb(LINE))
                    .child(
                        div()
                            .flex()
                            .flex_col()
                            .gap(px(6.))
                            .child(div().text_size(px(19.)).child(title))
                            .child(
                                div()
                                    .text_size(px(12.))
                                    .text_color(rgb(MUTED))
                                    .child(detail),
                            ),
                    )
                    .child(self.button(
                        if mic { "mic" } else { "accessibility" },
                        if granted {
                            "Allowed ✓"
                        } else {
                            "Allow access ↗"
                        },
                        !granted,
                        cx,
                        move |app, _, _| {
                            if !granted {
                                app.result(if mic {
                                    platform::request_microphone()
                                } else {
                                    platform::request_accessibility()
                                });
                            }
                        },
                    )),
            );
        }
        panel.child(div().my(px(20.)).text_size(px(12.)).line_height(px(21.)).text_color(rgb(MUTED)).child("In macOS Keyboard settings, set ‘Press Globe key to’ to ‘Do Nothing’. Choose a different shortcut for Apple Dictation. Allow Voco itself in Accessibility."))
            .child(div().flex().gap(px(10.)).child(self.button("reveal", "Reveal Voco ↗", false, cx, |app, _, _| app.result(platform::show_app())))
                .child(self.button("refresh-access", "Check again", true, cx, |app, _, _| app.controller.refresh_permissions())))
            .when(self.controller.permissions.accessibility && !self.controller.shortcut_running, |s| s.child(div().mt(px(16.)).text_color(rgb(0xff9d9d)).child("Keyboard monitoring is unavailable. Check Accessibility and restart Voco.")))
    }
    fn settings(&self, cx: &mut Context<Self>) -> Div {
        let mut tabs = div()
            .track_focus(&self.settings_focus)
            .on_key_down(cx.listener(|app, event: &KeyDownEvent, _, cx| {
                let tabs = [
                    SettingsTab::Output,
                    SettingsTab::Models,
                    SettingsTab::Access,
                    SettingsTab::Dictation,
                ];
                let index = app.tab as usize;
                let next = match event.keystroke.key.as_str() {
                    "right" | "down" => (index + 1) % 4,
                    "left" | "up" => (index + 3) % 4,
                    "home" => 0,
                    "end" => 3,
                    _ => return,
                };
                app.tab = tabs[next];
                cx.stop_propagation();
                cx.notify();
            }))
            .flex()
            .gap(px(24.))
            .border_b_1()
            .border_color(rgb(LINE))
            .mb(px(24.));
        for (tab, label) in [
            (SettingsTab::Output, "Output"),
            (SettingsTab::Models, "Models"),
            (SettingsTab::Access, "Access"),
            (SettingsTab::Dictation, "Dictation"),
        ] {
            tabs = tabs.child(
                Button::new(label)
                    .ghost()
                    .label(label)
                    .rounded(px(0.))
                    .px(px(0.))
                    .pb(px(13.))
                    .h(px(38.))
                    .border_0()
                    .border_b_2()
                    .border_color(rgb(if self.tab == tab { ORANGE } else { BG }))
                    .text_color(rgb(if self.tab == tab { TEXT } else { MUTED }))
                    .on_click(cx.listener(move |app, _, _, cx| {
                        app.tab = tab;
                        cx.notify();
                    })),
            );
        }
        let panel = match self.tab {
            SettingsTab::Models => self.models(cx), SettingsTab::Access => self.access(cx),
            SettingsTab::Dictation => div().flex().flex_col().gap(px(20.)).child(div().text_size(px(23.)).child("Speak into the app you're using."))
                .child("Hold Fn or Globe to talk. Release to finish.").child("Fn + Space starts or stops continuous dictation. Escape cancels.")
                .child(div().text_color(rgb(MUTED)).line_height(px(23.)).child("Keep the original text field focused. Voco inserts once and never sends your message. Review your words before sending them."))
                .child(div().mt(px(20.)).pt(px(24.)).border_t_1().border_color(rgb(LINE)).child(div().text_size(px(18.)).mb(px(10.)).child("Private by nature."))
                    .child(div().text_color(rgb(MUTED)).line_height(px(23.)).child("Speech recognition runs on your Mac. Only model downloads use the internet. No account or API key. Audio stays in memory while processing. Recent transcripts disappear when you quit."))),
            SettingsTab::Output => {
                let mut modes = div().flex().gap(px(8.)).my(px(20.));
                for (mode, label) in [(OutputMode::Fast,"Fast"),(OutputMode::Balanced,"Balanced"),(OutputMode::Accurate,"Accurate")] {
                    modes = modes.child(self.button(label, label, self.controller.settings.output_mode == mode, cx, move |app, _, _| { if !app.controller.session.active() { app.controller.settings.output_mode = mode; app.controller.save(); } }).disabled(self.controller.session.active()));
                }
                div().flex().flex_col().child(div().text_size(px(23.)).child("Your voice. A little more polished."))
                    .child(div().mt(px(8.)).text_color(rgb(MUTED)).child("Choose how your words are cleaned up. Changes apply immediately."))
                    .child(modes).child(div().text_color(rgb(MUTED)).line_height(px(22.)).child(match self.controller.settings.output_mode { OutputMode::Fast => "The speech model's original transcript, with nothing added.", OutputMode::Balanced => "Local rules remove fillers and spoken restarts. Quotes, code, links, and quantities stay intact.", OutputMode::Accurate => "Uses Balanced cleanup. Apple FoundationModels formatting is unavailable in the Rust build." }))
                    .when(self.controller.session.active(), |s| s.child(div().mt(px(12.)).text_color(rgb(ORANGE)).child("Finish dictating to change output quality.")))
                    .child(div().mt(px(30.)).pt(px(24.)).border_t_1().border_color(rgb(LINE)).flex().justify_between().items_center()
                        .child(div().flex().flex_col().gap(px(6.)).child("Keep recent words").child(div().text_size(px(12.)).text_color(rgb(MUTED)).child("Until Voco quits. Turning off clears recent text immediately.")))
                        .child(self.button("retention", if self.controller.settings.keep_last_transcript { "On ✓" } else { "Off" }, self.controller.settings.keep_last_transcript, cx, |app, _, _| app.controller.set_retention(!app.controller.settings.keep_last_transcript))))
                    .child(div().mt(px(14.)).text_size(px(11.)).text_color(rgb(MUTED)).child("Words from failed insertion always remain available for recovery."))
            }
        };
        div()
            .child(self.heading(
                "A voice that fits your flow.",
                "A few thoughtful choices. Everything stays on this Mac.",
            ))
            .child(tabs)
            .child(panel)
    }
    fn stats(&self, cx: &mut Context<Self>) -> Div {
        let summary = self
            .controller
            .settings
            .summary(chrono::Local::now().date_naive());
        let mut page = div().child(self.heading("Look how far your voice takes you.", "Your usage totals stay on this Mac. Your audio and transcript text never go to disk.")).child(self.metrics());
        for (label, value) in [
            ("Dictation sessions", summary.sessions.to_string()),
            ("Best streak", format!("{} days", summary.best_streak)),
        ] {
            page = page.child(
                div()
                    .flex()
                    .justify_between()
                    .py(px(20.))
                    .border_b_1()
                    .border_color(rgb(LINE))
                    .child(div().text_color(rgb(MUTED)).child(label))
                    .child(div().text_size(px(21.)).child(value)),
            );
        }
        for (goal, label, value) in [
            (
                true,
                "Daily word goal",
                format!("{} words", self.controller.settings.daily_goal),
            ),
            (
                false,
                "Your typing speed",
                format!("{} words / min", self.controller.settings.typing_wpm),
            ),
        ] {
            page = page.child(
                div()
                    .flex()
                    .justify_between()
                    .items_center()
                    .py(px(22.))
                    .border_b_1()
                    .border_color(rgb(LINE))
                    .child(label)
                    .child(
                        div()
                            .flex()
                            .items_center()
                            .gap(px(12.))
                            .child(self.button(
                                if goal { "goal-minus" } else { "speed-minus" },
                                "−",
                                false,
                                cx,
                                move |app, _, _| {
                                    if goal {
                                        app.controller.settings.daily_goal = app
                                            .controller
                                            .settings
                                            .daily_goal
                                            .saturating_sub(100)
                                            .max(100);
                                    } else {
                                        app.controller.settings.typing_wpm = app
                                            .controller
                                            .settings
                                            .typing_wpm
                                            .saturating_sub(10)
                                            .max(10);
                                    }
                                    app.controller.save();
                                },
                            ))
                            .child(div().w(px(120.)).text_center().child(value))
                            .child(self.button(
                                if goal { "goal-plus" } else { "speed-plus" },
                                "+",
                                false,
                                cx,
                                move |app, _, _| {
                                    if goal {
                                        app.controller.settings.daily_goal =
                                            (app.controller.settings.daily_goal + 100).min(10000);
                                    } else {
                                        app.controller.settings.typing_wpm =
                                            (app.controller.settings.typing_wpm + 10).min(200);
                                    }
                                    app.controller.save();
                                },
                            )),
                    ),
            );
        }
        page.child(
            div()
                .mt(px(20.))
                .text_size(px(12.))
                .text_color(rgb(MUTED))
                .child("Time given back is estimated using your typing speed."),
        )
    }
    fn footer(&self, window: &mut Window, cx: &mut Context<Self>) -> Div {
        let mut footer = div()
            .flex_shrink_0()
            .border_t_1()
            .border_color(rgb(LINE))
            .px(px(32.))
            .py(px(16.))
            .flex()
            .flex_col()
            .gap(px(9.));
        if let Session::Recovery { message, text } = &self.controller.session {
            footer = footer.child(
                div()
                    .flex()
                    .flex_col()
                    .gap(px(12.))
                    .p(px(16.))
                    .bg(rgb(0x181310))
                    .rounded(px(12.))
                    .child(
                        div()
                            .text_color(rgb(ORANGE))
                            .child("Your dictation needs attention"),
                    )
                    .child(
                        div()
                            .id("recovery-text")
                            .max_h(px(120.))
                            .overflow_y_scroll()
                            .child(literal_text("recovery-words".into(), text, window, cx)),
                    )
                    .child(
                        div()
                            .text_size(px(12.))
                            .text_color(rgb(MUTED))
                            .child(message.clone()),
                    )
                    .child(
                        div()
                            .flex()
                            .gap(px(10.))
                            .when(!text.is_empty(), |s| {
                                s.child(self.button(
                                    "recover",
                                    "Copy your words",
                                    true,
                                    cx,
                                    |app, _, _| {
                                        app.controller.copy_recovery();
                                        if !matches!(
                                            app.controller.session,
                                            Session::Recovery { .. }
                                        ) {
                                            app.copied_until =
                                                Some(Instant::now() + Duration::from_secs(2));
                                        }
                                    },
                                ))
                            })
                            .child(self.button("dismiss", "Dismiss", false, cx, |app, _, _| {
                                app.controller.cancel()
                            })),
                    ),
            );
        }
        footer = footer.child(
            div()
                .flex()
                .items_center()
                .justify_between()
                .gap(px(16.))
                .child(
                    div()
                        .flex()
                        .items_center()
                        .gap(px(9.))
                        .child(div().size(px(6.)).rounded_full().bg(rgb(
                            if self.controller.ready() {
                                0xb9cbbd
                            } else {
                                ORANGE
                            },
                        )))
                        .child(self.controller.status().to_owned()),
                )
                .child(
                    if matches!(
                        self.controller.session,
                        Session::Armed | Session::Listening { .. } | Session::Finishing
                    ) {
                        self.button("cancel-session", "Cancel · Esc", false, cx, |app, _, _| {
                            app.controller.cancel()
                        })
                        .into_any_element()
                    } else {
                        div()
                            .text_size(px(11.))
                            .text_color(rgb(MUTED))
                            .child(
                                if self
                                    .copied_until
                                    .is_some_and(|until| until > Instant::now())
                                {
                                    "Copied ✓"
                                } else {
                                    "Processed on your Mac"
                                },
                            )
                            .into_any_element()
                    },
                ),
        );
        if !self.controller.notice.is_empty() {
            footer = footer.child(
                div()
                    .text_size(px(11.))
                    .text_color(rgb(MUTED))
                    .child(self.controller.notice.clone()),
            );
        }
        footer
    }
    fn verify(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        let Some(mut verification) = self.verification.take() else {
            return;
        };
        if verification.started.elapsed() > Duration::from_secs(90) {
            eprintln!("Native UI verification timed out");
            std::process::exit(1);
        }
        if let Some(receiver) = &verification.capture {
            match receiver.try_recv() {
                Ok(Ok(())) => {
                    verification.capture = None;
                    verification.stage += 1;
                    verification.stage_started = Instant::now();
                }
                Ok(Err(message)) => {
                    eprintln!("Native screenshot capture failed. {message}");
                    std::process::exit(1);
                }
                Err(std::sync::mpsc::TryRecvError::Empty) => {}
                Err(std::sync::mpsc::TryRecvError::Disconnected) => {
                    eprintln!("Native screenshot worker stopped");
                    std::process::exit(1);
                }
            }
            self.verification = Some(verification);
            return;
        }
        if verification.stage_started.elapsed() < Duration::from_millis(400) {
            self.verification = Some(verification);
            return;
        }
        let fail = |message: &str| {
            eprintln!("{message}");
            std::process::exit(1);
        };
        match verification.stage {
            0..=10 => {
                let stage = verification.stage;
                match stage {
                    0 => self.page = Page::Home,
                    1 => self.page = Page::Transcripts,
                    2 => self.page = Page::Stats,
                    3..=6 => {
                        self.page = Page::Settings;
                        self.tab = [
                            SettingsTab::Output,
                            SettingsTab::Models,
                            SettingsTab::Access,
                            SettingsTab::Dictation,
                        ][stage - 3];
                    }
                    7 => {
                        self.page = Page::Home;
                        window.resize(size(px(820.), px(640.)));
                    }
                    8 => {
                        window.resize(size(px(1080.), px(800.)));
                        self.controller.session = Session::Recovery {
                            text: "Native verification recovery words.".into(),
                            message: "Verification scenario. Your words are safe to copy.".into(),
                        };
                    }
                    9 | 10 => {
                        self.overlay.update(
                            if stage == 9 {
                                "Listening"
                            } else {
                                "Transcribing"
                            },
                            if stage == 9 { 0.42 } else { 0. },
                            true,
                            cx,
                        );
                    }
                    _ => {}
                }
                dashboard_visibility(true);
                let directory = verification.directory.clone();
                let number = if stage >= 9 {
                    self.overlay.window_number()
                } else {
                    objc2::MainThreadMarker::new()
                        .and_then(|main| {
                            objc2_app_kit::NSApplication::sharedApplication(main)
                                .windows()
                                .iter()
                                .find(|w| w.title().to_string() == "Voco")
                                .map(|w| w.windowNumber())
                        })
                        .expect("dashboard window number")
                };
                let (sender, receiver) = std::sync::mpsc::channel();
                verification.capture = Some(receiver);
                std::thread::spawn(move || {
                    std::thread::sleep(Duration::from_millis(350));
                    let output = directory.join(format!("{stage}.png"));
                    let result = std::process::Command::new("/usr/sbin/screencapture")
                        .args(["-x", "-o", "-l"])
                        .arg(number.to_string())
                        .arg(output)
                        .status()
                        .map_err(|error| error.to_string())
                        .and_then(|status| {
                            if status.success() {
                                Ok(())
                            } else {
                                Err(status.to_string())
                            }
                        });
                    let _ = sender.send(result);
                });
                self.verification = Some(verification);
                cx.notify();
                return;
            }
            11 => {
                self.search
                    .update(cx, |input, cx| input.set_value("literal", window, cx));
                if self.transcript_count(cx) != 1 {
                    fail("Transcript search did not filter literal text");
                }
                self.search
                    .update(cx, |input, cx| input.set_value("", window, cx));
                if self.transcript_count(cx) != 2 {
                    fail("Clearing transcript search did not restore rows");
                }
                self.controller.cancel();
                self.page = Page::Home;
                self.practice.update(cx, |input, cx| {
                    input.set_value("", window, cx);
                    input.replace_and_mark_text_in_range(
                        None,
                        "Before 😀 after",
                        Some(7..9),
                        window,
                        cx,
                    );
                    input.unmark_text(window, cx);
                    input.focus(window, cx);
                });
            }
            12 => {
                let target = self.practice_target(window, cx).unwrap_or_else(|| {
                    fail("Native practice focus capture failed");
                    unreachable!()
                });
                let (replacement, caret) = target
                    .replace(&target, "Rust")
                    .expect("Unicode replacement");
                self.apply_practice_update(replacement, caret, window, cx);
                let after = self
                    .practice_target(window, cx)
                    .expect("practice after replacement");
                let expected =
                    crate::practice::PracticeTarget::capture("Before Rust after", 11..11)
                        .expect("expected caret");
                verification.practice_verified =
                    self.practice.read(cx).value() == "Before Rust after" && after == expected;
                if !verification.practice_verified {
                    fail("Native practice replacement or caret failed");
                }
                if target.replace(&after, "Changed").is_ok() {
                    fail("Changed practice text was accepted");
                }
                self.apply_practice_update("Before Rust café 😀 after".into(), 18, window, cx);
                let unicode = self
                    .practice_target(window, cx)
                    .expect("Unicode caret snapshot");
                let expected_unicode =
                    crate::practice::PracticeTarget::capture("Before Rust café 😀 after", 18..18)
                        .expect("Unicode expected caret");
                if unicode != expected_unicode {
                    fail("Unicode caret was not preserved");
                }
                self.practice.update(cx, |input, cx| {
                    input.replace_and_mark_text_in_range(Some(0..0), "x", None, window, cx)
                });
                if self.practice_target(window, cx).is_some() {
                    fail("Composing input was accepted for dictation");
                }
                self.practice
                    .update(cx, |input, cx| input.unmark_text(window, cx));
                let native_key = objc2::MainThreadMarker::new().and_then(|main| {
                    objc2_app_kit::NSApplication::sharedApplication(main).keyWindow()
                });
                self.overlay.update("Listening", 0.4, true, cx);
                self.overlay.verify().expect("GPUI overlay focus safety");
                if !self.practice.focus_handle(cx).is_focused(window) {
                    fail("Overlay stole input focus");
                }
                let after_key = objc2::MainThreadMarker::new().and_then(|main| {
                    objc2_app_kit::NSApplication::sharedApplication(main).keyWindow()
                });
                if native_key != after_key {
                    fail("Overlay changed the native key window");
                }
                self.overlay.update("Ready", 0., false, cx);
            }
            13 => request_dashboard_close(),
            14 => {
                verification.close_verified = !platform::dashboard_visible();
                if !verification.close_verified {
                    fail("Closing did not hide the native dashboard");
                }
                let status = std::env::current_exe()
                    .and_then(|exe| std::process::Command::new(exe).arg("--show").status());
                if !status.is_ok_and(|s| s.success()) {
                    fail("Second-instance show failed");
                }
            }
            15 => {
                if !platform::dashboard_visible() {
                    fail("Second-instance show did not reveal dashboard");
                }
                for index in 0..11 {
                    if !verification
                        .directory
                        .join(format!("{index}.png"))
                        .is_file()
                    {
                        fail("Native page screenshot missing");
                    }
                }
                let report = serde_json::json!({"runtime":"rust", "ui":"gpui", "pagesRendered":4,"screenshots":11,"settingsTabsRendered":4,"compactWindow":true,"recoveryRendered":true,"trayCreated":true,"practiceInsertion":verification.practice_verified,"practiceRejectsChangedText":true,"practiceRejectsComposition":true,"overlayScreenshots":2,"overlayPreservesFocus":true,"overlayIgnoresMouse":true,"closeHidesDashboard":verification.close_verified,"secondInstanceShow":true,"microphone":self.controller.permissions.microphone,"accessibility":self.controller.permissions.accessibility,"shortcut":self.controller.shortcut_running,"status":self.controller.status(),"transcriptSearch":true,"transcriptPersistence":false});
                std::fs::write(
                    verification.directory.join("report.json"),
                    serde_json::to_vec_pretty(&report).expect("report JSON"),
                )
                .expect("verification report");
                cx.quit();
            }
            _ => {}
        }
        verification.stage += 1;
        verification.stage_started = Instant::now();
        self.verification = Some(verification);
        cx.notify();
    }
}
impl Render for VocoApp {
    fn render(&mut self, window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let content = match self.page {
            Page::Home => self.home(window, cx),
            Page::Settings => self.settings(cx),
            Page::Stats => self.stats(cx),
            Page::Transcripts => div()
                .child(self.heading(
                    "A thought worth keeping.",
                    "Recent dictations, here until you quit Voco.",
                ))
                .child(
                    div()
                        .flex()
                        .gap(px(10.))
                        .items_center()
                        .child(
                            div()
                                .flex_1()
                                .child(Input::new(&self.search).rounded_full()),
                        )
                        .child(self.button(
                            "clear-search",
                            "Clear",
                            false,
                            cx,
                            |app, window, cx| {
                                app.search.update(cx, |input, cx| {
                                    input.set_value("", window, cx);
                                    input.focus(window, cx);
                                });
                            },
                        )),
                )
                .child(
                    div()
                        .mt(px(15.))
                        .text_size(px(11.))
                        .text_color(rgb(MUTED))
                        .child(format!("{} recent dictations", self.transcript_count(cx))),
                )
                .child(div().mt(px(8.)).child(self.transcripts(50, window, cx))),
        };
        div()
            .size_full()
            .flex()
            .bg(rgb(BG))
            .text_color(rgb(TEXT))
            .font_family("Manrope")
            .text_size(px(13.))
            .on_key_down(cx.listener(|app, event: &KeyDownEvent, window, cx| {
                if app.page == Page::Transcripts
                    && event.keystroke.key == "escape"
                    && app.search.focus_handle(cx).is_focused(window)
                {
                    app.search
                        .update(cx, |input, cx| input.set_value("", window, cx));
                    cx.stop_propagation();
                    cx.notify();
                }
            }))
            .child(self.sidebar(cx))
            .child(
                div()
                    .flex_1()
                    .min_w_0()
                    .h_full()
                    .flex()
                    .flex_col()
                    .child(
                        div()
                            .id("page-scroll")
                            .flex_1()
                            .min_h_0()
                            .overflow_y_scroll()
                            .px(px(36.))
                            .pt(px(34.))
                            .pb(px(30.))
                            .child(if platform::reduced_motion() {
                                content.into_any_element()
                            } else {
                                content
                                    .with_animation(
                                        SharedString::from(format!(
                                            "page-{:?}-{}",
                                            self.page, self.tab as u8
                                        )),
                                        Animation::new(Duration::from_millis(160))
                                            .with_easing(ease_out_quint()),
                                        |element, progress| {
                                            element
                                                .opacity(0.75 + progress * 0.25)
                                                .mt(px((1. - progress) * 4.))
                                        },
                                    )
                                    .into_any_element()
                            }),
                    )
                    .child(self.footer(window, cx)),
            )
    }
}
