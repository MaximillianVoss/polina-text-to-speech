import * as Speech from 'expo-speech';
import type { SpeechAdapter } from './speech';

/** The only file that connects the pure controller to Expo's speech engine. */
export const expoSpeechAdapter: SpeechAdapter = {
  maxTextLength: Speech.maxSpeechInputLength,
  stop: () => Speech.stop(),
  speak: (text, options) => {
    Speech.speak(text, {
      language: options.language,
      pitch: 1,
      rate: 1,
      onStart: options.onStart,
      onDone: options.onDone,
      onStopped: options.onStopped,
      onError: (error) => options.onError(error),
    });
  },
};
