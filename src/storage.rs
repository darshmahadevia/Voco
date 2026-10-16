use crate::domain::{ModelId, OutputMode};
use anyhow::{Context, Result, bail};
use chrono::{Days, Local, NaiveDate};
use serde::{Deserialize, Serialize};
use std::{
    collections::BTreeMap,
    fs,
    path::{Path, PathBuf},
};

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UsageDay {
    pub words: u64,
    pub seconds: f64,
    pub sessions: u64,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct Settings {
    pub keep_last_transcript: bool,
    pub output_mode: OutputMode,
    pub selected_model: ModelId,
    pub daily_goal: u32,
    pub typing_wpm: u32,
    pub days: BTreeMap<String, UsageDay>,
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            keep_last_transcript: true,
            output_mode: OutputMode::Fast,
            selected_model: ModelId::Moonshine,
            daily_goal: 500,
            typing_wpm: 40,
            days: BTreeMap::new(),
        }
    }
}

#[derive(Default)]
pub struct Summary {
    pub words: u64,
    pub sessions: u64,
    pub seconds_saved: f64,
    pub streak: u64,
    pub best_streak: u64,
}

impl Settings {
    pub fn load(root: &Path) -> Result<Self> {
        let path = root.join("settings.json");
        let settings = match fs::read(&path) {
            Ok(data) => serde_json::from_slice(&data).context(
                "Voco settings are unreadable. Restore settings.json or move it aside to reset.",
            )?,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
                if std::env::var_os("VOCO_DATA_DIR").is_some() {
                    Self::default()
                } else {
                    Self::migrate()
                }
            }
            Err(error) => return Err(error).context("Could not read Voco settings"),
        };
        settings.validate()?;
        Ok(settings)
    }

    fn migrate() -> Self {
        let mut settings = Self::default();
        let Some(home) = std::env::var_os("HOME") else {
            return settings;
        };
        for domain in ["org.vocoapp.Voco", "org.vocoapp.Voco.Native"] {
            let path = PathBuf::from(&home).join(format!("Library/Preferences/{domain}.plist"));
            let Ok(plist::Value::Dictionary(values)) = plist::Value::from_file(path) else {
                continue;
            };
            settings.import_legacy(&values);
        }
        settings
    }

    fn import_legacy(&mut self, values: &plist::Dictionary) {
        if let Some(value) = values
            .get("keepLastTranscript")
            .and_then(plist::Value::as_boolean)
        {
            self.keep_last_transcript = value;
        }
        if let Some(value) = values.get("outputMode").and_then(plist::Value::as_string)
            && let Ok(mode) = serde_json::from_value(serde_json::Value::String(value.to_owned()))
        {
            self.output_mode = mode;
        }
        if let Some(value) = values
            .get("selectedSpeechModel")
            .and_then(plist::Value::as_string)
            && let Ok(model) = serde_json::from_value(serde_json::Value::String(value.to_owned()))
        {
            self.selected_model = model;
        }
        if let Some(bytes) = values.get("usageStats.v1").and_then(plist::Value::as_data) {
            #[derive(Deserialize)]
            #[serde(rename_all = "camelCase")]
            struct LegacyUsage {
                days: BTreeMap<String, UsageDay>,
                daily_goal: u32,
                typing_wpm: u32,
            }
            if let Ok(usage) = serde_json::from_slice::<LegacyUsage>(bytes) {
                let candidate = Settings {
                    days: usage.days,
                    daily_goal: usage.daily_goal,
                    typing_wpm: usage.typing_wpm,
                    ..self.clone()
                };
                if candidate.validate().is_ok() {
                    *self = candidate;
                }
            }
        }
    }

    pub fn validate(&self) -> Result<()> {
        if !(100..=10000).contains(&self.daily_goal) || !(10..=200).contains(&self.typing_wpm) {
            bail!("Usage preferences are outside the supported range.");
        }
        for (date, day) in &self.days {
            NaiveDate::parse_from_str(date, "%Y-%m-%d").context("Invalid usage date")?;
            if !day.seconds.is_finite() || day.seconds < 0.0 {
                bail!("Invalid dictation duration.");
            }
        }
        Ok(())
    }

    pub fn save(&self, root: &Path) -> Result<()> {
        self.validate()?;
        fs::create_dir_all(root)?;
        let path = root.join("settings.json.tmp");
        let mut options = fs::OpenOptions::new();
        options.write(true).create(true).truncate(true);
        #[cfg(unix)]
        {
            use std::os::unix::fs::OpenOptionsExt;
            options.mode(0o600);
        }
        let mut file = options.open(&path)?;
        use std::io::Write;
        file.write_all(&serde_json::to_vec_pretty(self)?)?;
        file.sync_all()?;
        fs::rename(path, root.join("settings.json"))?;
        Ok(())
    }

    pub fn record(&mut self, text: &str, seconds: f64) {
        let words = text
            .split_whitespace()
            .filter(|s| s.chars().any(char::is_alphanumeric))
            .count() as u64;
        if words == 0 || !seconds.is_finite() || seconds < 0.0 {
            return;
        }
        let day = self
            .days
            .entry(Local::now().format("%Y-%m-%d").to_string())
            .or_default();
        day.words += words;
        day.seconds += seconds;
        day.sessions += 1;
    }

    pub fn summary(&self, today: NaiveDate) -> Summary {
        let mut result = Summary::default();
        let mut seconds = 0.0;
        let mut previous = None;
        let mut run = 0;
        for (key, day) in &self.days {
            if day.words == 0 {
                continue;
            }
            result.words += day.words;
            result.sessions += day.sessions;
            seconds += day.seconds;
            let Ok(date) = NaiveDate::parse_from_str(key, "%Y-%m-%d") else {
                continue;
            };
            run = if previous == date.checked_sub_days(Days::new(1)) {
                run + 1
            } else {
                1
            };
            result.best_streak = result.best_streak.max(run);
            previous = Some(date);
        }
        result.seconds_saved =
            (result.words as f64 / self.typing_wpm as f64 * 60.0 - seconds).max(0.0);
        let mut cursor = today;
        if !self.active_day(cursor) {
            cursor = cursor.pred_opt().unwrap_or(cursor);
        }
        while self.active_day(cursor) {
            result.streak += 1;
            let Some(previous) = cursor.pred_opt() else {
                break;
            };
            cursor = previous;
        }
        result
    }
    fn active_day(&self, date: NaiveDate) -> bool {
        self.days
            .get(&date.format("%Y-%m-%d").to_string())
            .is_some_and(|day| day.words > 0)
    }
}

pub fn app_directory() -> Result<PathBuf> {
    if let Some(path) = std::env::var_os("VOCO_DATA_DIR") {
        return Ok(PathBuf::from(path));
    }
    Ok(
        PathBuf::from(std::env::var_os("HOME").context("HOME is not set")?)
            .join("Library/Application Support/Voco"),
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn totals_and_streak_use_calendar_days() {
        let mut settings = Settings::default();
        for date in ["2026-10-13", "2026-10-14", "2026-10-15"] {
            settings.days.insert(
                date.into(),
                UsageDay {
                    words: 100,
                    seconds: 20.0,
                    sessions: 1,
                },
            );
        }
        let summary = settings.summary(NaiveDate::from_ymd_opt(2026, 10, 16).unwrap());
        assert_eq!(
            (
                summary.words,
                summary.sessions,
                summary.streak,
                summary.best_streak
            ),
            (300, 3, 3, 3)
        );
        assert_eq!(summary.seconds_saved, 390.0);
    }
    #[test]
    fn settings_store_no_transcripts_and_reject_invalid_usage() {
        let settings = Settings::default();
        let json = serde_json::to_string(&settings).unwrap();
        assert!(!json.contains("lastTranscript"));
        assert!(!json.contains("audio"));
        let mut invalid = settings;
        invalid.typing_wpm = 0;
        assert!(invalid.validate().is_err());
    }
    #[test]
    fn invalid_legacy_usage_preserves_privacy_and_model_preferences() {
        let mut settings = Settings::default();
        let mut values = plist::Dictionary::new();
        values.insert("keepLastTranscript".into(), plist::Value::Boolean(false));
        values.insert(
            "selectedSpeechModel".into(),
            plist::Value::String("whisper".into()),
        );
        values.insert("outputMode".into(), plist::Value::String("balanced".into()));
        values.insert(
            "usageStats.v1".into(),
            plist::Value::Data(br#"{"days":{},"dailyGoal":0,"typingWpm":0}"#.to_vec()),
        );
        settings.import_legacy(&values);
        assert!(!settings.keep_last_transcript);
        assert_eq!(settings.selected_model, ModelId::Whisper);
        assert_eq!(settings.output_mode, OutputMode::Balanced);
        assert_eq!((settings.daily_goal, settings.typing_wpm), (500, 40));
    }
}
