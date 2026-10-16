use serde::{Deserialize, Serialize};

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum ModelId {
    #[default]
    Moonshine,
    Parakeet,
    Whisper,
}

impl ModelId {
    pub const ALL: [Self; 3] = [Self::Moonshine, Self::Parakeet, Self::Whisper];
    pub fn label(self) -> &'static str {
        match self {
            Self::Moonshine => "Moonshine",
            Self::Parakeet => "Parakeet",
            Self::Whisper => "Whisper",
        }
    }
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum OutputMode {
    #[default]
    Fast,
    Balanced,
    Accurate,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum CaptureMode {
    Hold,
    Continuous,
}

#[derive(Clone, Debug, Default, PartialEq)]
pub enum Session {
    #[default]
    Idle,
    Armed,
    Listening {
        mode: CaptureMode,
    },
    Finishing,
    Recovery {
        message: String,
        text: String,
    },
}

impl Session {
    pub fn active(&self) -> bool {
        !matches!(self, Self::Idle)
    }
}
