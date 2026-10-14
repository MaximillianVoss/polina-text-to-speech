import { useEffect, useRef, useState } from 'react';
import {
  KeyboardAvoidingView,
  Platform,
  Pressable,
  ScrollView,
  StatusBar,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import { SafeAreaProvider, SafeAreaView } from 'react-native-safe-area-context';
import { LanguageSelector } from './src/LanguageSelector';
import { expoSpeechAdapter } from './src/expoSpeech';
import {
  INITIAL_SPEECH_STATE,
  SpeechController,
  speechInputLimit,
  type SpeechState,
} from './src/speech';

function SpeechScreen() {
  const [text, setText] = useState('');
  const [selectedIndex, setSelectedIndex] = useState(0);
  const [inputError, setInputError] = useState<string | null>(null);
  const [speechState, setSpeechState] = useState<SpeechState>(INITIAL_SPEECH_STATE);
  const controllerRef = useRef<SpeechController | null>(null);
  const latestAction = useRef(0);
  const inputLimit = speechInputLimit(expoSpeechAdapter.maxTextLength);

  useEffect(() => {
    // Create a fresh controller for each mounted subscription, including Strict Mode.
    const controller = new SpeechController(expoSpeechAdapter);
    controllerRef.current = controller;
    const unsubscribe = controller.subscribe(setSpeechState);
    return () => {
      ++latestAction.current;
      controllerRef.current = null;
      unsubscribe();
      void controller.dispose();
    };
  }, []);

  const handleSay = async () => {
    const controller = controllerRef.current;
    if (controller === null) return;
    const action = ++latestAction.current;
    setInputError(null);
    const result = await controller.say(text, selectedIndex);
    if (controllerRef.current !== controller || action !== latestAction.current) return;
    if (!result.ok && ['empty', 'too-long', 'invalid-language'].includes(result.reason)) {
      setInputError(result.message);
    }
  };

  const handleStop = () => {
    ++latestAction.current;
    setInputError(null);
    void controllerRef.current?.stop();
  };

  const changeText = (value: string) => {
    ++latestAction.current;
    setText(value);
    setInputError(null);
  };

  const changeLanguage = (index: number) => {
    ++latestAction.current;
    setSelectedIndex(index);
    setInputError(null);
  };

  const stopDisabled = speechState.status === 'idle';
  const hasSpeechError = speechState.status === 'error';

  return (
    <SafeAreaView style={styles.screen}>
      <StatusBar barStyle="dark-content" />
      <KeyboardAvoidingView
        style={styles.screen}
        behavior={Platform.OS === 'ios' ? 'padding' : undefined}
      >
        <ScrollView
          contentContainerStyle={styles.scrollContent}
          keyboardShouldPersistTaps="handled"
        >
          <View style={styles.content}>
            <View style={styles.heading}>
              <Text style={styles.eyebrow}>ASSIGNMENT 14 · TEXT TO SPEECH</Text>
              <Text style={styles.title} accessibilityRole="header">Give your words{ '\n' }a voice.</Text>
              <Text style={styles.subtitle}>Choose a language, type a sentence, then tap SAY IT.</Text>
            </View>

            <View style={styles.card}>
              <LanguageSelector selectedIndex={selectedIndex} onSelect={changeLanguage} />
              <View style={styles.fieldSection}>
                <View style={styles.fieldHeading}>
                  <Text style={styles.label}>Your text</Text>
                  <Text style={styles.counter} accessibilityLabel={`${text.length} of ${inputLimit} characters used`}>
                    {text.length} / {inputLimit}
                  </Text>
                </View>
                <TextInput
                  value={text}
                  onChangeText={changeText}
                  multiline
                  maxLength={inputLimit}
                  placeholder="Write something to say…"
                  placeholderTextColor="#858fa5"
                  textAlignVertical="top"
                  style={[styles.textInput, inputError !== null && styles.invalidInput]}
                  accessibilityLabel="Text to read aloud"
                  accessibilityHint="Enter the text, then tap SAY IT to hear it in the selected language"
                  autoCorrect
                  spellCheck
                />
                {inputError !== null && (
                  <Text style={styles.inputError} accessibilityRole="alert" accessibilityLiveRegion="assertive">
                    {inputError}
                  </Text>
                )}
              </View>

              <View style={styles.actions}>
                <Pressable
                  onPress={() => void handleSay()}
                  style={({ pressed }) => [styles.button, styles.sayButton, pressed && styles.pressed]}
                  accessibilityRole="button"
                  accessibilityLabel="SAY IT"
                  accessibilityHint="Stops any previous speech and reads the entered text"
                >
                  <Text style={styles.sayButtonText}>SAY IT</Text>
                </Pressable>
                <Pressable
                  onPress={handleStop}
                  disabled={stopDisabled}
                  style={({ pressed }) => [styles.button, styles.stopButton, stopDisabled && styles.disabled, pressed && styles.pressed]}
                  accessibilityRole="button"
                  accessibilityLabel="STOP"
                  accessibilityHint="Stops reading and clears pending speech"
                  accessibilityState={{ disabled: stopDisabled }}
                >
                  <Text style={styles.stopButtonText}>STOP</Text>
                </Pressable>
              </View>

              <View style={[styles.status, hasSpeechError && styles.errorStatus]}>
                <View style={[styles.statusDot, hasSpeechError && styles.errorDot]} />
                <Text
                  style={[styles.statusText, hasSpeechError && styles.errorStatusText]}
                  accessibilityLiveRegion="polite"
                  accessibilityRole={hasSpeechError ? 'alert' : 'text'}
                >
                  {speechState.message}
                </Text>
              </View>
            </View>

            <View style={styles.help}>
              <Text style={styles.helpTitle}>A small listening tip</Text>
              <Text style={styles.helpText}>The selected language changes pronunciation. It does not translate your text.</Text>
              <Text style={styles.helpText}>Voices depend on your device. If there is no sound, check volume and silent mode.</Text>
            </View>
          </View>
        </ScrollView>
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}

export default function App() {
  return (
    <SafeAreaProvider>
      <SpeechScreen />
    </SafeAreaProvider>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: '#f3f5fb' },
  scrollContent: { flexGrow: 1, alignItems: 'center', paddingHorizontal: 20, paddingVertical: 30 },
  content: { width: '100%', maxWidth: 640, gap: 24 },
  heading: { gap: 12, paddingHorizontal: 4 },
  eyebrow: { fontSize: 11, fontWeight: '700', letterSpacing: 1.3, color: '#5265c3', lineHeight: 18 },
  title: { color: '#202b48', fontSize: 34, fontWeight: '700', letterSpacing: -0.7, lineHeight: 42 },
  subtitle: { color: '#66728c', fontSize: 16, lineHeight: 25, maxWidth: 430 },
  card: { backgroundColor: '#ffffff', padding: 20, borderRadius: 22, borderColor: '#e1e6f2', borderWidth: 1, gap: 24 },
  fieldSection: { gap: 10 },
  fieldHeading: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: 8 },
  label: { color: '#253250', fontSize: 16, fontWeight: '600' },
  counter: { color: '#7a859c', fontSize: 12 },
  textInput: { minHeight: 168, maxHeight: 280, padding: 16, backgroundColor: '#f8f9fc', borderRadius: 14, borderWidth: 1, borderColor: '#d8dfed', color: '#253250', fontSize: 17, lineHeight: 26 },
  invalidInput: { borderColor: '#c55757' },
  inputError: { color: '#aa3434', fontSize: 14, lineHeight: 21 },
  actions: { flexDirection: 'row', flexWrap: 'wrap', gap: 12 },
  button: { flex: 1, minWidth: 100, minHeight: 52, alignItems: 'center', justifyContent: 'center', borderRadius: 13, paddingHorizontal: 18, paddingVertical: 15 },
  sayButton: { backgroundColor: '#4358d0' },
  stopButton: { backgroundColor: '#eef1f9', borderWidth: 1, borderColor: '#dbe1ef' },
  sayButtonText: { color: '#ffffff', fontSize: 15, letterSpacing: 1, fontWeight: '700' },
  stopButtonText: { color: '#435079', fontSize: 15, letterSpacing: 1, fontWeight: '700' },
  disabled: { opacity: 0.45 },
  pressed: { opacity: 0.75 },
  status: { borderRadius: 12, backgroundColor: '#eef8f6', padding: 12, flexDirection: 'row', alignItems: 'center', gap: 9 },
  statusDot: { width: 7, height: 7, borderRadius: 4, backgroundColor: '#3a867a' },
  statusText: { color: '#376c64', fontSize: 13, lineHeight: 20, flex: 1 },
  errorStatus: { backgroundColor: '#fff0f0' },
  errorDot: { backgroundColor: '#b44c4c' },
  errorStatusText: { color: '#a34040' },
  help: { paddingHorizontal: 6, gap: 8, paddingBottom: 12 },
  helpTitle: { color: '#475572', fontWeight: '600', fontSize: 14 },
  helpText: { color: '#738099', fontSize: 13, lineHeight: 21 },
});
