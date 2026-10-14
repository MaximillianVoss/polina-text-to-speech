import SegmentedControl from '@react-native-segmented-control/segmented-control';
import { StyleSheet, Text, View } from 'react-native';
import { LANGUAGES, languageFromIndex } from './speech';

interface LanguageSelectorProps {
  selectedIndex: number;
  onSelect: (index: number) => void;
}

export function LanguageSelector({ selectedIndex, onSelect }: LanguageSelectorProps) {
  const selectedLanguage = languageFromIndex(selectedIndex);
  return (
    <View style={styles.container}>
      <Text style={styles.label}>Speech language</Text>
      <SegmentedControl
        values={LANGUAGES.map((language) => language.label)}
        selectedIndex={selectedIndex}
        onChange={(event) => {
          const nextIndex = event.nativeEvent.selectedSegmentIndex;
          if (languageFromIndex(nextIndex) !== undefined) onSelect(nextIndex);
        }}
        appearance="light"
        tintColor="#4358d0"
        backgroundColor="#e9edf8"
        fontStyle={{ fontSize: 14, fontWeight: '500', color: '#34405c' }}
        activeFontStyle={{ fontSize: 14, fontWeight: '600', color: '#ffffff' }}
        style={styles.control}
        accessibilityLabel="Select the speech language: English, Finnish or Swedish"
        accessibilityHint="Changes the voice language for the next time you tap SAY IT"
      />
      <Text style={styles.hint}>Example: {selectedLanguage?.example ?? ''}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { gap: 12 },
  label: { color: '#253250', fontSize: 16, fontWeight: '600' },
  control: { height: 44, width: '100%' },
  hint: { color: '#66728c', fontSize: 13, lineHeight: 20 },
});
