use std::{ops::Range, sync::OnceLock};

use regex::Regex;

use crate::domain::OutputMode;

const QUANTITY: &str = r"(?:[+\-−][ \t]*)?(?:\p{N}+(?:[.,:/\-]\p{N}+)*|[.,]\p{N}+)(?:[ \t]*%)?";
const WORD: &str = r"[\p{L}\p{N}]+(?:['’\-][\p{L}\p{N}]+)*";

#[derive(Clone, Copy)]
enum Boundary {
    Any,
    NonAlphanumericBefore,
    NonWordBefore,
    SingleQuote,
    Function,
}

struct Patterns {
    protected: Vec<(Regex, Boundary)>,
    tokens: Regex,
    filler: Regex,
    abbreviation: Regex,
    letters: Regex,
}

fn patterns() -> &'static Patterns {
    static PATTERNS: OnceLock<Patterns> = OnceLock::new();
    PATTERNS.get_or_init(|| {
        let rules = [
            (r"(?s)```.*?(?:```|$)|`[^`\r\n]*(?:`|$)".to_owned(), Boundary::Any),
            (r#"(?s)"(?:\\.|[^"\\])*(?:"|$)|“[^”]*(?:”|$)|‘[^’]*(?:’|$)"#.to_owned(), Boundary::Any),
            (r"(?s)'(?:\\.|[^'\\])*'".to_owned(), Boundary::SingleQuote),
            (r#"(?:https?://|www\.)[^\s<>"`]+|[\p{L}\p{N}._%+\-]+@[\p{L}\p{N}.\-]+\.[\p{L}]{2,}"#.to_owned(), Boundary::Any),
            (r#"(?:[~/]|[A-Za-z]:\\)[^\s,;!?"`]+"#.to_owned(), Boundary::NonAlphanumericBefore),
            (r"--?[\p{L}][\w=\-]*".to_owned(), Boundary::NonWordBefore),
            (r"\b[\p{L}\p{N}]+(?:[_./:\\-][\p{L}\p{N}]+)+\b|\b(?:[A-Z]\.){2,}|[$@#][\p{L}_][\p{L}\p{N}_]*".to_owned(), Boundary::Any),
            (r"\b[\p{L}_][\p{L}\p{N}_]*".to_owned(), Boundary::Function),
            (r"(?:-m|--message)(?:[ \t]+|=)[^\s]+".to_owned(), Boundary::NonWordBefore),
            (format!(r"{QUANTITY}(?:[ \t]+(?:um|uh)\b)?|\b(?:UM|UH)\b"), Boundary::Any),
        ];
        Patterns {
            protected: rules.into_iter().map(|(pattern, boundary)| (Regex::new(&pattern).unwrap(), boundary)).collect(),
            tokens: Regex::new(&format!(r"{WORD}|[^\s]")).unwrap(),
            filler: Regex::new(r"^u(?:m+|h+)$").unwrap(),
            abbreviation: Regex::new(r"\b(?:[A-Z]\.){2,}").unwrap(),
            letters: Regex::new(r"^\p{L}+$").unwrap(),
        }
    })
}

fn protected_ranges(text: &str) -> Vec<Range<usize>> {
    let mut ranges = Vec::new();
    for (pattern, boundary) in &patterns().protected {
        let mut cursor = 0;
        while let Some(found) = pattern.find_at(text, cursor) {
            let before = text[..found.start()].chars().next_back();
            let after = text[found.end()..].chars().next();
            let valid = match boundary {
                Boundary::Any => true,
                Boundary::NonAlphanumericBefore => !before.is_some_and(char::is_alphanumeric),
                Boundary::NonWordBefore => !before.is_some_and(|c| c.is_alphanumeric() || c == '_'),
                Boundary::SingleQuote => {
                    !before.is_some_and(char::is_alphanumeric)
                        && !after.is_some_and(char::is_alphanumeric)
                }
                Boundary::Function => after == Some('('),
            };
            if valid {
                cursor = found.end();
                ranges.push(found.range());
            } else {
                // A rejected apostrophe or flag may overlap a later valid literal.
                cursor = found.start() + text[found.start()..].chars().next().unwrap().len_utf8();
            }
        }
    }
    ranges
}

struct Token<'a> {
    range: Range<usize>,
    text: &'a str,
    protected: bool,
}

impl Token<'_> {
    fn ordinary_word(&self) -> bool {
        !self.protected && patterns().letters.is_match(self.text)
    }
}

fn tokens(text: &str) -> Vec<Token<'_>> {
    let protected = protected_ranges(text);
    patterns()
        .tokens
        .find_iter(text)
        .map(|found| Token {
            protected: protected
                .iter()
                .any(|range| range.start < found.end() && found.start() < range.end),
            range: found.range(),
            text: found.as_str(),
        })
        .collect()
}

fn has_line_break(text: &str) -> bool {
    text.contains(['\r', '\n'])
}

fn pronoun_or_determiner(word: &str) -> bool {
    [
        "i", "you", "he", "she", "it", "we", "they", "me", "him", "her", "us", "them", "my",
        "your", "his", "its", "our", "their", "a", "an", "the", "this", "that", "these", "those",
        "some", "any", "each", "every", "all", "both", "no", "neither", "either", "who", "what",
        "which",
    ]
    .contains(&word)
}

fn adjective_or_adverb(word: &str) -> bool {
    [
        "red",
        "blue",
        "green",
        "black",
        "white",
        "yellow",
        "orange",
        "pink",
        "purple",
        "brown",
        "gray",
        "grey",
        "wrong",
        "right",
        "correct",
        "incorrect",
        "true",
        "false",
        "old",
        "new",
        "big",
        "small",
        "large",
        "little",
        "high",
        "low",
        "hot",
        "cold",
        "early",
        "late",
        "fast",
        "slow",
        "quickly",
        "slowly",
        "now",
        "then",
        "here",
        "there",
        "today",
        "tomorrow",
        "yesterday",
    ]
    .contains(&word)
}

fn action_head(word: &str) -> bool {
    [
        "send", "ask", "call", "book", "use", "run", "keep", "bring", "buy", "pack", "include",
        "charge", "pay", "set", "visit", "write", "read", "make", "take", "tell", "say", "please",
        "do", "try", "start", "stop", "go", "come", "get", "put", "open", "close", "save",
        "delete", "change", "move", "email",
    ]
    .contains(&word)
}

// Apple sentence and POS APIs are deliberately isolated behind these conservative rules.
fn sentence_starts(raw: &str, parts: &[Token<'_>]) -> Vec<bool> {
    let abbreviations: Vec<_> = patterns()
        .abbreviation
        .find_iter(raw)
        .map(|m| m.range())
        .collect();
    let protected = protected_ranges(raw);
    let mut starts = vec![false; parts.len()];
    for index in 0..parts.len() {
        if index == 0 {
            starts[index] = true;
            continue;
        }
        if protected.iter().any(|range| {
            range.start < parts[index].range.start && parts[index].range.start < range.end
        }) {
            continue;
        }
        let mut previous = index - 1;
        while previous > 0
            && matches!(
                parts[previous].text,
                "\"" | "'" | "”" | "’" | ")" | "]" | "}"
            )
        {
            previous -= 1;
        }
        let punctuation = &parts[previous];
        if !matches!(punctuation.text, "." | "!" | "?")
            || parts[index - 1].range.end == parts[index].range.start
        {
            continue;
        }
        if punctuation.text == "." {
            if let Some(abbreviation) = abbreviations
                .iter()
                .find(|range| range.end == punctuation.range.end)
            {
                let head = parts[index].text.to_lowercase();
                let before = raw[..abbreviation.start].trim_end().to_lowercase();
                let place = ["in the", "in", "to the", "to", "from the", "from", "the"]
                    .iter()
                    .any(|suffix| before.ends_with(suffix));
                starts[index] = place
                    && parts[index].ordinary_word()
                    && (action_head(&head) || adjective_or_adverb(&head));
                continue;
            }
            if previous > 0 && parts[previous - 1].range.end == punctuation.range.start {
                let word = parts[previous - 1].text.to_lowercase();
                if matches!(
                    word.as_str(),
                    "dr" | "mr"
                        | "mrs"
                        | "ms"
                        | "prof"
                        | "sr"
                        | "jr"
                        | "rev"
                        | "st"
                        | "vs"
                        | "etc"
                        | "e.g"
                        | "i.e"
                ) || (word.chars().count() == 1
                    && parts[previous - 1].text.chars().all(char::is_uppercase))
                {
                    continue;
                }
            }
        }
        starts[index] = true;
    }
    starts
}

pub fn polish(raw: &str, mode: OutputMode) -> (String, String) {
    match mode {
        OutputMode::Fast => (raw.to_owned(), String::new()),
        OutputMode::Balanced => (clean(raw), String::new()),
        OutputMode::Accurate => {
            let text = clean(raw);
            let notice = if text.is_empty() {
                String::new()
            } else {
                "FoundationModels is unavailable in the Rust app. Kept basic cleanup.".to_owned()
            };
            (text, notice)
        }
    }
}

pub fn clean(raw: &str) -> String {
    let parts = tokens(raw);
    let boundaries = sentence_starts(raw, &parts);
    let mut removed = vec![false; parts.len()];
    let mut exposed = vec![false; parts.len()];
    let mut sentence_start = 0;
    let mut index = 0;
    while index < parts.len() {
        let token = &parts[index];
        if boundaries[index]
            || (index > 0 && has_line_break(&raw[parts[index - 1].range.end..token.range.start]))
        {
            sentence_start = index;
        }
        if !token.protected {
            let lower = token.text.to_lowercase();
            let pair = lower == "never"
                && index + 1 < parts.len()
                && !parts[index + 1].protected
                && parts[index + 1].text.eq_ignore_ascii_case("mind")
                && !has_line_break(&raw[token.range.end..parts[index + 1].range.start]);
            let restart = pair && {
                let prefix: Vec<_> = (sentence_start..index).filter(|&i| !removed[i]).collect();
                let next = index + 2;
                let delimiter = |i: usize| matches!(parts[i].text, "," | ";" | ":" | "—");
                if prefix.is_empty()
                    || (index > 0 && delimiter(index - 1))
                    || (next < parts.len() && delimiter(next))
                {
                    true
                } else if let Some(&first) = prefix.first() {
                    if next < parts.len()
                        && parts[first].ordinary_word()
                        && parts[next].ordinary_word()
                    {
                        let head = parts[first].text.to_lowercase();
                        (head == parts[next].text.to_lowercase() && !pronoun_or_determiner(&head))
                            || (prefix.len() == 1
                                && adjective_or_adverb(&head)
                                && (next + 1 == parts.len()
                                    || matches!(parts[next + 1].text, "." | "!" | "?")
                                    || parts[next + 1].text.eq_ignore_ascii_case("never")
                                    || parts[next + 1].text.eq_ignore_ascii_case("nevermind")))
                    } else {
                        false
                    }
                } else {
                    false
                }
            };
            if lower == "nevermind" || restart {
                let mut end = index + usize::from(pair);
                while end + 1 < parts.len()
                    && !parts[end + 1].protected
                    && matches!(parts[end + 1].text, "," | "." | "!" | "?" | ";" | ":")
                {
                    end += 1;
                }
                removed[sentence_start..=end].fill(true);
                if end + 1 < parts.len() {
                    exposed[end + 1] = true;
                }
                index = end;
                sentence_start = end + 1;
            } else if patterns().filler.is_match(&lower) {
                removed[index] = true;
                let at_start = (sentence_start..index)
                    .all(|i| removed[i] || matches!(parts[i].text, "(" | "[" | "{"));
                let previous_comma =
                    index > 0 && parts[index - 1].text == "," && !parts[index - 1].protected;
                let mut end = index;
                if index > 0
                    && index + 1 < parts.len()
                    && !parts[index - 1].protected
                    && !parts[index + 1].protected
                    && matches!(
                        (parts[index - 1].text, parts[index + 1].text),
                        ("(", ")") | ("[", "]") | ("{", "}")
                    )
                {
                    removed[index - 1] = true;
                    removed[index + 1] = true;
                    end = index + 1;
                }
                while end + 1 < parts.len()
                    && !parts[end + 1].protected
                    && (parts[end + 1].text == ","
                        || (at_start && matches!(parts[end + 1].text, "." | "!" | "?" | ";" | ":")))
                {
                    end += 1;
                    removed[end] = true;
                }
                if previous_comma {
                    let previous_word = if index >= 2 {
                        parts[index - 2].text.to_lowercase()
                    } else {
                        String::new()
                    };
                    let next_word = parts
                        .get(end + 1)
                        .map(|token| token.text.to_lowercase())
                        .unwrap_or_default();
                    let list = parts[sentence_start..index].iter().any(|token| {
                        matches!(
                            token.text.to_lowercase().as_str(),
                            "bring" | "buy" | "pack" | "include"
                        )
                    });
                    let keep_comma = matches!(
                        previous_word.as_str(),
                        "yes" | "no" | "well" | "okay" | "ok"
                    ) || next_word == "not"
                        || (list && parts.get(end + 1).is_some_and(Token::ordinary_word));
                    if !keep_comma {
                        removed[index - 1] = true;
                    }
                }
                if at_start && end + 1 < parts.len() {
                    exposed[end + 1] = true;
                }
                index = end;
            }
        }
        index += 1;
    }
    if !removed.iter().any(|&removed| removed) {
        return raw.to_owned();
    }

    let mut deleted = vec![false; raw.len()];
    for (index, token) in parts.iter().enumerate() {
        if removed[index] {
            deleted[token.range.clone()].fill(true);
        }
    }
    let mut runs = Vec::new();
    let mut cursor = 0;
    while cursor < deleted.len() {
        if deleted[cursor] {
            let start = cursor;
            while cursor < deleted.len() && deleted[cursor] {
                cursor += 1;
            }
            runs.push(start..cursor);
        } else {
            cursor += 1;
        }
    }
    for range in runs.into_iter().rev() {
        let mut end = range.end;
        while end < raw.len() && matches!(raw.as_bytes()[end], b' ' | b'\t') {
            end += 1;
        }
        if end > range.end {
            deleted[range.end..end].fill(true);
        } else {
            let mut start = range.start;
            while start > 0 && matches!(raw.as_bytes()[start - 1], b' ' | b'\t') {
                start -= 1;
            }
            deleted[start..range.start].fill(true);
        }
    }
    let mut capitalize = vec![false; raw.len()];
    for (index, token) in parts.iter().enumerate() {
        if exposed[index]
            && !removed[index]
            && token.ordinary_word()
            && token.text == token.text.to_lowercase()
        {
            capitalize[token.range.start] = true;
        }
    }
    let mut output = String::with_capacity(raw.len());
    cursor = 0;
    while cursor < raw.len() {
        if deleted[cursor] {
            while cursor < raw.len() && deleted[cursor] {
                cursor += 1;
            }
            if cursor < raw.len()
                && output
                    .chars()
                    .next_back()
                    .is_some_and(|c| !c.is_whitespace() && !"([{\n\r".contains(c))
            {
                let next = raw[cursor..].chars().next().unwrap();
                if next.is_alphanumeric() || "\"`“‘".contains(next) {
                    output.push(' ');
                }
            }
            continue;
        }
        let character = raw[cursor..].chars().next().unwrap();
        if capitalize[cursor] {
            output.extend(character.to_uppercase());
        } else {
            output.push(character);
        }
        cursor += character.len_utf8();
    }
    if output.trim().is_empty() {
        String::new()
    } else {
        output
    }
}

#[cfg(test)]
fn accepts(candidate: &str, original: &str) -> bool {
    let baseline = clean(original);
    if candidate.is_empty() || candidate.len() > baseline.len() * 2 + 64 {
        return false;
    }
    let word = Regex::new(WORD).unwrap();
    let before: Vec<_> = word.find_iter(&baseline).collect();
    let after: Vec<_> = word.find_iter(candidate).collect();
    if before.is_empty()
        || before.len() != after.len()
        || before.iter().zip(&after).any(|(old, new)| {
            old.as_str().to_lowercase() != new.as_str().to_lowercase()
                || (old.as_str() != old.as_str().to_lowercase() && old.as_str() != new.as_str())
        })
    {
        return false;
    }
    let quantity = Regex::new(QUANTITY).unwrap();
    let quantities = |text: &str| {
        quantity
            .find_iter(text)
            .map(|found| found.as_str().replace([' ', '\t'], ""))
            .collect::<Vec<_>>()
    };
    if quantities(&baseline) != quantities(candidate) {
        return false;
    }
    let whole_quantity = Regex::new(&format!("^(?:{QUANTITY})$")).unwrap();
    let literals = |text: &str| {
        let words: Vec<_> = word.find_iter(text).map(|found| found.start()).collect();
        let mut literals: Vec<_> = protected_ranges(text)
            .into_iter()
            .filter_map(|range| {
                let literal = &text[range.clone()];
                if whole_quantity.is_match(literal) {
                    None
                } else {
                    Some((
                        words.partition_point(|&start| start < range.start),
                        literal.to_owned(),
                    ))
                }
            })
            .collect();
        literals.sort();
        literals
    };
    if literals(&baseline) != literals(candidate) {
        return false;
    }
    let lines = Regex::new(r"\r\n|\r|\n").unwrap();
    let line_boundaries = |text: &str| {
        lines
            .find_iter(text)
            .map(|line| {
                (
                    word.find_iter(text)
                        .take_while(|w| w.start() < line.start())
                        .count(),
                    line.as_str().to_owned(),
                )
            })
            .collect::<Vec<_>>()
    };
    if line_boundaries(&baseline) != line_boundaries(candidate) {
        return false;
    }
    let symbol = Regex::new(r"[\p{S}*/%]").unwrap();
    let operator = Regex::new(r"[\p{Sm}*/]").unwrap();
    let symbols = |text: &str| {
        symbol
            .find_iter(text)
            .map(|found| {
                let position = word
                    .find_iter(text)
                    .take_while(|w| w.start() < found.start())
                    .count();
                let neighbor = |character: Option<char>| {
                    if operator.is_match(found.as_str()) {
                        character
                            .filter(|c| !c.is_whitespace())
                            .map(|c| c.to_lowercase().to_string())
                            .unwrap_or_default()
                    } else {
                        String::new()
                    }
                };
                (
                    position,
                    found.as_str().to_owned(),
                    neighbor(text[..found.start()].chars().next_back()),
                    neighbor(text[found.end()..].chars().next()),
                )
            })
            .collect::<Vec<_>>()
    };
    symbols(&baseline) == symbols(candidate)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde::Deserialize;

    #[derive(Deserialize)]
    struct Fixture {
        id: String,
        input: String,
        balanced: String,
        #[serde(default)]
        preserved: Vec<String>,
    }

    fn check_fixtures(json: &str) {
        let fixtures: Vec<Fixture> = serde_json::from_str(json).unwrap();
        assert!(!fixtures.is_empty());
        for fixture in fixtures {
            let result = clean(&fixture.input);
            assert_eq!(
                result, fixture.balanced,
                "{}: {:?}",
                fixture.id, fixture.input
            );
            assert_eq!(clean(&result), result, "{} must be idempotent", fixture.id);
            for literal in fixture.preserved {
                assert!(result.contains(&literal), "{} lost {literal:?}", fixture.id);
            }
            assert_eq!(
                polish(&fixture.input, OutputMode::Fast),
                (fixture.input.clone(), String::new()),
                "{} fast",
                fixture.id
            );
            assert_eq!(
                polish(&fixture.input, OutputMode::Balanced),
                (fixture.balanced.clone(), String::new()),
                "{} balanced",
                fixture.id
            );
            let (accurate, notice) = polish(&fixture.input, OutputMode::Accurate);
            assert_eq!(
                accurate, fixture.balanced,
                "{} accurate fallback",
                fixture.id
            );
            if accurate.is_empty() {
                assert!(notice.is_empty());
            } else {
                assert!(
                    notice.contains("FoundationModels")
                        && notice.contains("unavailable")
                        && notice.contains("Kept basic cleanup")
                );
            }
        }
    }

    #[test]
    fn all_swift_balanced_fixtures() {
        check_fixtures(include_str!("../Tests/fixtures/cleanup-cases.json"));
    }

    #[test]
    fn swift_literal_safety_and_idempotence() {
        check_fixtures(include_str!("../Tests/fixtures/cleanup-swift-checks.json"));
    }

    #[test]
    fn swift_invalid_model_edits() {
        #[derive(Deserialize)]
        struct Edit {
            original: String,
            candidate: String,
        }
        let edits: Vec<Edit> =
            serde_json::from_str(include_str!("../Tests/fixtures/cleanup-invalid-edits.json"))
                .unwrap();
        assert!(!edits.is_empty());
        for edit in edits {
            assert_eq!(
                clean(&edit.original),
                edit.original,
                "Changed protected source"
            );
            assert!(
                !accepts(&edit.candidate, &edit.original),
                "Accepted {:?} for {:?}",
                edit.candidate,
                edit.original
            );
        }
    }

    #[test]
    fn safe_punctuation_preserves_literals_and_quantities() {
        for (original, candidate) in [
            ("Pay .5 dollars", "Pay .5 dollars."),
            ("Pay -.5 dollars", "Pay -.5 dollars."),
            ("Pay ,5 dollars", "Pay ,5 dollars."),
            ("Pay -,5 dollars", "Pay -,5 dollars."),
            ("Pay $12 to Alice", "Pay $12 to Alice."),
            (
                "hello Alice can you send it today",
                "Hello Alice, can you send it today?",
            ),
            ("Run `echo um` then wait", "Run `echo um`, then wait."),
            ("Set the rate to 12 %", "Set the rate to 12%"),
        ] {
            assert!(
                accepts(candidate, original),
                "Rejected {candidate:?} for {original:?}"
            );
        }
    }

    #[test]
    fn empty_and_long_transcripts_need_no_model() {
        for raw in ["", "um uh", "Wrong nevermind."] {
            assert_eq!(
                polish(raw, OutputMode::Accurate),
                (String::new(), String::new())
            );
        }
        let raw = "a".repeat(2_001);
        let (result, notice) = polish(&raw, OutputMode::Accurate);
        assert_eq!(result, raw);
        assert!(notice.contains("unavailable"));
    }
}
