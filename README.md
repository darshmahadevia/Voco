# Voco

Speak into the app you're using. Voco turns your voice into text on your Mac.

Hold **Fn** or **Globe**, say what you want to write, and release. Voco transcribes your speech and inserts the text at your cursor. It lives in the menu bar, so you can close the dashboard and keep dictating.

Speech recognition runs locally. You don't need an account, an API key, or a subscription. After you download a speech model, you can dictate offline.

![Voco dashboard with shortcut guidance and recent transcripts](docs/images/voco-dashboard.png)

*Dashboard preview with sample transcripts and usage data.*

## What you can do

- Dictate into text fields in other apps.
- Hold a key to talk, or use **Fn + Space** to start and stop a longer dictation.
- Choose Moonshine, Parakeet, or Whisper for speech recognition.
- Keep your words as spoken, or clean up fillers and punctuation before insertion.
- Copy recent transcripts while Voco is open, including text it couldn't insert.

Voco inserts the finished transcript after you stop speaking. Review the text before you send it.

## Try Voco

Voco currently supports **Apple Silicon Macs running macOS 26 or newer** and **English dictation**. It's an early project, and compatibility with text fields varies between apps.

For now, build Voco from source. There is no published installer. You'll need Node.js 22 or newer, Swift 6.2 or newer, Apple's Command Line Tools, and CMake.

```sh
git clone https://github.com/darshmahadevia/Voco.git
cd Voco
npm ci
./scripts/install.sh
open ~/Applications/Voco.app
```

The installer puts Voco in `~/Applications`. Local builds are not notarized by Apple. See the [development guide](docs/development.md) for build options and signing details.

## First setup

1. Open Voco from the menu bar and choose **Open Dashboard**.
2. Follow setup to download and load a speech model. The download needs an internet connection and stays on your Mac across app updates.
3. Allow microphone and keyboard access when prompted. Voco uses macOS Accessibility access to detect shortcuts and insert text. Follow the setup instructions to approve the helper app.
4. In macOS Keyboard settings, set **Press Globe key to** to **Do Nothing**. Use a different shortcut for Apple Dictation.
5. Try the practice field, then place your cursor in another app and dictate.

Hold **Fn** or **Globe** to speak and release to finish. Press **Fn + Space** to start continuous dictation, then press it again to finish. **Escape** cancels recording or pending transcription.

If you switch apps or text fields before insertion, Voco keeps the transcript available to copy. Selected text is replaced when Voco inserts a transcript. Voco doesn't press Return or send messages for you.

## Choose how your words are cleaned up

**Fast** keeps the speech model's transcript. **Balanced** removes fillers and spoken restarts and tidies punctuation. **Accurate** adds formatting with Apple's on-device model when Apple Intelligence is available. If that step is unavailable, Voco uses Balanced cleanup.

You choose the speech model separately. These settings describe the cleanup Voco applies, and recognition can still make mistakes. See [output modes and examples](docs/local-dictation.md) for details.

## Your audio and text

Audio is processed on your Mac. Voco doesn't save recordings or transcript history to disk. Recent transcripts stay in memory until you quit. Turning off **Keep last transcript** clears retained text. If insertion fails, Voco keeps the completed text available for copying.

Preferences and usage totals are saved locally. Speech models are stored in `~/Library/Application Support/Voco/models`. Model downloads use the internet. Dictation works offline once a model is installed.

## Report a problem

[Open an issue](https://github.com/darshmahadevia/Voco/issues) with your macOS version, Mac chip, selected model, and steps to reproduce the problem. For insertion problems, include the destination app. Use sample text instead of private recordings or transcripts.

For code changes, start with the [development guide](docs/development.md) and [architecture](docs/architecture.md).

## License and credits

Voco is licensed under the [MIT License](LICENSE). Speech engines, model weights, and fonts have their own licenses. The app includes [third-party notices](Resources/licenses), including attribution for Moonshine, NVIDIA Parakeet, FluidAudio, OpenAI Whisper, and whisper.cpp.
