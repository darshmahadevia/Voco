#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Action {
    Pressed,
    Released,
    Cancelled,
    ToggleContinuous,
    Escape,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
enum Trigger {
    #[default]
    Idle,
    Held,
    Blocked,
    Chord,
}

#[derive(Default)]
pub struct HoldGesture {
    trigger: Trigger,
    space_down: bool,
}

#[derive(Default)]
pub struct KeyEvent {
    pub trigger_down: bool,
    pub other_modifier: bool,
    pub key_pressed: bool,
    pub space_pressed: bool,
    pub space_released: bool,
    pub repeat: bool,
}

impl HoldGesture {
    pub fn update(&mut self, event: KeyEvent) -> Option<Action> {
        if event.space_released {
            self.space_down = false;
        }
        if event.space_pressed {
            let fresh = !self.space_down && !event.repeat;
            self.space_down = true;
            if event.trigger_down && !event.other_modifier && self.trigger != Trigger::Blocked {
                if !fresh {
                    return None;
                }
                self.trigger = Trigger::Chord;
                return Some(Action::ToggleContinuous);
            }
        }
        if !event.trigger_down {
            let held = self.trigger == Trigger::Held;
            self.trigger = Trigger::Idle;
            return held.then_some(Action::Released);
        }
        if self.trigger == Trigger::Idle {
            self.trigger = if event.other_modifier || event.key_pressed {
                Trigger::Blocked
            } else {
                Trigger::Held
            };
            return (self.trigger == Trigger::Held).then_some(Action::Pressed);
        }
        if matches!(self.trigger, Trigger::Held | Trigger::Chord)
            && (event.other_modifier || event.key_pressed)
        {
            self.trigger = Trigger::Blocked;
            return Some(Action::Cancelled);
        }
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn hold_releases_and_chord_does_not() {
        let mut gesture = HoldGesture::default();
        assert_eq!(
            gesture.update(KeyEvent {
                trigger_down: true,
                ..Default::default()
            }),
            Some(Action::Pressed)
        );
        assert_eq!(gesture.update(KeyEvent::default()), Some(Action::Released));
        assert_eq!(
            gesture.update(KeyEvent {
                trigger_down: true,
                ..Default::default()
            }),
            Some(Action::Pressed)
        );
        assert_eq!(
            gesture.update(KeyEvent {
                trigger_down: true,
                key_pressed: true,
                space_pressed: true,
                ..Default::default()
            }),
            Some(Action::ToggleContinuous)
        );
        assert_eq!(
            gesture.update(KeyEvent {
                trigger_down: true,
                key_pressed: true,
                space_pressed: true,
                repeat: true,
                ..Default::default()
            }),
            None
        );
        assert_eq!(gesture.update(KeyEvent::default()), None);
    }
    #[test]
    fn modifier_chords_cancel_and_remain_blocked() {
        let mut gesture = HoldGesture::default();
        gesture.update(KeyEvent {
            trigger_down: true,
            ..Default::default()
        });
        assert_eq!(
            gesture.update(KeyEvent {
                trigger_down: true,
                other_modifier: true,
                ..Default::default()
            }),
            Some(Action::Cancelled)
        );
        assert_eq!(
            gesture.update(KeyEvent {
                trigger_down: true,
                ..Default::default()
            }),
            None
        );
        assert_eq!(gesture.update(KeyEvent::default()), None);
    }
    #[test]
    fn space_chord_promotes_hold_and_ignores_repeats_and_fn_release() {
        let mut gesture = HoldGesture::default();
        assert_eq!(
            gesture.update(KeyEvent {
                trigger_down: true,
                ..Default::default()
            }),
            Some(Action::Pressed)
        );
        assert_eq!(
            gesture.update(KeyEvent {
                trigger_down: true,
                key_pressed: true,
                space_pressed: true,
                ..Default::default()
            }),
            Some(Action::ToggleContinuous)
        );
        assert_eq!(
            gesture.update(KeyEvent {
                trigger_down: true,
                key_pressed: true,
                space_pressed: true,
                repeat: true,
                ..Default::default()
            }),
            None
        );
        assert_eq!(
            gesture.update(KeyEvent {
                trigger_down: false,
                ..Default::default()
            }),
            None
        );
        assert_eq!(
            gesture.update(KeyEvent {
                trigger_down: true,
                key_pressed: true,
                space_pressed: true,
                repeat: true,
                ..Default::default()
            }),
            None
        );
        assert_eq!(
            gesture.update(KeyEvent {
                trigger_down: true,
                space_released: true,
                ..Default::default()
            }),
            Some(Action::Pressed)
        );
        assert_eq!(
            gesture.update(KeyEvent {
                trigger_down: true,
                key_pressed: true,
                space_pressed: true,
                ..Default::default()
            }),
            Some(Action::ToggleContinuous)
        );
    }
    #[test]
    fn blocked_combination_requires_fn_release_before_space_chord() {
        let mut gesture = HoldGesture::default();
        assert_eq!(
            gesture.update(KeyEvent {
                trigger_down: true,
                other_modifier: true,
                ..Default::default()
            }),
            None
        );
        assert_eq!(
            gesture.update(KeyEvent {
                trigger_down: true,
                key_pressed: true,
                space_pressed: true,
                ..Default::default()
            }),
            None
        );
        assert_eq!(
            gesture.update(KeyEvent {
                trigger_down: false,
                space_released: true,
                ..Default::default()
            }),
            None
        );
        assert_eq!(
            gesture.update(KeyEvent {
                trigger_down: true,
                key_pressed: true,
                space_pressed: true,
                ..Default::default()
            }),
            Some(Action::ToggleContinuous)
        );
    }
    #[test]
    fn unrelated_key_cancels_hold_and_space_does_not_restart_it() {
        let mut gesture = HoldGesture::default();
        assert_eq!(
            gesture.update(KeyEvent {
                trigger_down: true,
                ..Default::default()
            }),
            Some(Action::Pressed)
        );
        assert_eq!(
            gesture.update(KeyEvent {
                trigger_down: true,
                key_pressed: true,
                ..Default::default()
            }),
            Some(Action::Cancelled)
        );
        assert_eq!(
            gesture.update(KeyEvent {
                trigger_down: true,
                key_pressed: true,
                space_pressed: true,
                ..Default::default()
            }),
            None
        );
        assert_eq!(
            gesture.update(KeyEvent {
                trigger_down: false,
                space_released: true,
                ..Default::default()
            }),
            None
        );
        assert_eq!(
            gesture.update(KeyEvent {
                trigger_down: true,
                ..Default::default()
            }),
            Some(Action::Pressed)
        );
    }
    #[test]
    fn space_held_before_fn_cannot_suppress_hold_release() {
        let mut gesture = HoldGesture::default();
        assert_eq!(
            gesture.update(KeyEvent {
                trigger_down: false,
                key_pressed: true,
                space_pressed: true,
                ..Default::default()
            }),
            None
        );
        assert_eq!(
            gesture.update(KeyEvent {
                trigger_down: true,
                ..Default::default()
            }),
            Some(Action::Pressed)
        );
        assert_eq!(
            gesture.update(KeyEvent {
                trigger_down: true,
                key_pressed: true,
                space_pressed: true,
                repeat: true,
                ..Default::default()
            }),
            None
        );
        assert_eq!(
            gesture.update(KeyEvent {
                trigger_down: false,
                ..Default::default()
            }),
            Some(Action::Released)
        );
    }
    #[test]
    fn hold_emits_one_start_and_one_release() {
        let mut gesture = HoldGesture::default();
        assert_eq!(
            gesture.update(KeyEvent {
                trigger_down: true,
                ..Default::default()
            }),
            Some(Action::Pressed)
        );
        assert_eq!(
            gesture.update(KeyEvent {
                trigger_down: true,
                ..Default::default()
            }),
            None
        );
        assert_eq!(
            gesture.update(KeyEvent {
                trigger_down: false,
                ..Default::default()
            }),
            Some(Action::Released)
        );
        assert_eq!(
            gesture.update(KeyEvent {
                trigger_down: false,
                ..Default::default()
            }),
            None
        );
    }
    #[test]
    fn keyboard_combination_cancels_until_the_trigger_is_released() {
        let mut gesture = HoldGesture::default();
        assert_eq!(
            gesture.update(KeyEvent {
                trigger_down: true,
                ..Default::default()
            }),
            Some(Action::Pressed)
        );
        assert_eq!(
            gesture.update(KeyEvent {
                trigger_down: true,
                key_pressed: true,
                ..Default::default()
            }),
            Some(Action::Cancelled)
        );
        assert_eq!(
            gesture.update(KeyEvent {
                trigger_down: true,
                ..Default::default()
            }),
            None
        );
        assert_eq!(
            gesture.update(KeyEvent {
                trigger_down: false,
                ..Default::default()
            }),
            None
        );
        assert_eq!(
            gesture.update(KeyEvent {
                trigger_down: true,
                ..Default::default()
            }),
            Some(Action::Pressed)
        );
    }
    #[test]
    fn existing_modifier_combination_does_not_start_dictation() {
        let mut gesture = HoldGesture::default();
        assert_eq!(
            gesture.update(KeyEvent {
                trigger_down: true,
                other_modifier: true,
                ..Default::default()
            }),
            None
        );
        assert_eq!(
            gesture.update(KeyEvent {
                trigger_down: false,
                ..Default::default()
            }),
            None
        );
        assert_eq!(
            gesture.update(KeyEvent {
                trigger_down: true,
                ..Default::default()
            }),
            Some(Action::Pressed)
        );
    }
}
