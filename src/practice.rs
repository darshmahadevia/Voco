use anyhow::{Result, ensure};
use std::ops::Range;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PracticeTarget {
    value: String,
    selection: Range<usize>,
}

impl PracticeTarget {
    pub fn capture(value: &str, selection: Range<usize>) -> Result<Self> {
        ensure!(
            selection.start <= selection.end && selection.end <= value.chars().count(),
            "The practice selection is invalid."
        );
        Ok(Self {
            value: value.into(),
            selection,
        })
    }
    pub fn replace(&self, current: &Self, text: &str) -> Result<(String, usize)> {
        ensure!(
            self == current,
            "The practice field changed while recording. Copy your transcript instead."
        );
        let before: String = self.value.chars().take(self.selection.start).collect();
        let after: String = self.value.chars().skip(self.selection.end).collect();
        Ok((
            format!("{before}{text}{after}"),
            self.selection.start + text.chars().count(),
        ))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn replaces_unicode_selection_and_preserves_caret() {
        let target = PracticeTarget::capture("Before 😀 after", 7..8).unwrap();
        assert_eq!(
            target.replace(&target, "Rust café").unwrap(),
            ("Before Rust café after".into(), 16)
        );
    }
    #[test]
    fn refuses_changed_text_and_selection() {
        let target = PracticeTarget::capture("Before 😀 after", 7..8).unwrap();
        assert!(
            target
                .replace(&PracticeTarget::capture("Changed", 0..0).unwrap(), "Rust")
                .is_err()
        );
        assert!(
            target
                .replace(
                    &PracticeTarget::capture("Before 😀 after", 8..8).unwrap(),
                    "Rust"
                )
                .is_err()
        );
        assert!(PracticeTarget::capture("😀", 0..2).is_err());
    }
}
