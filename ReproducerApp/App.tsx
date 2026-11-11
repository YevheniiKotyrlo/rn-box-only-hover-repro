import { ScrollView, StatusBar, StyleSheet, Text, View } from 'react-native';
import {
  SafeAreaProvider,
  useSafeAreaInsets,
} from 'react-native-safe-area-context';

function App() {
  return (
    <SafeAreaProvider>
      <StatusBar barStyle="dark-content" />
      <HoverTargets />
    </SafeAreaProvider>
  );
}

function HoverTargets() {
  const safeAreaInsets = useSafeAreaInsets();

  return (
    <View style={[styles.screen, { paddingTop: safeAreaInsets.top + 24 }]}>
      <View accessible accessibilityLabel="auto View" style={styles.target}>
        <Text style={styles.label}>pointerEvents="auto"</Text>
      </View>
      <View
        accessible
        accessibilityLabel="box-only View"
        pointerEvents="box-only"
        style={styles.target}
      >
        <Text style={styles.label}>pointerEvents="box-only"</Text>
      </View>
      <ScrollView scrollEnabled={false} style={styles.scrollView}>
        <View
          accessible
          accessibilityLabel="View inside a ScrollView with scrollEnabled false"
          style={styles.target}
        >
          <Text style={styles.label}>
            inside a ScrollView with scrollEnabled=false
          </Text>
        </View>
      </ScrollView>
    </View>
  );
}

const styles = StyleSheet.create({
  screen: {
    flex: 1,
    gap: 24,
    paddingHorizontal: 24,
    backgroundColor: '#ffffff',
  },
  scrollView: {
    flexGrow: 0,
  },
  target: {
    height: 140,
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: 2,
    borderColor: '#1f6feb',
    borderRadius: 12,
    backgroundColor: '#ddf4ff',
  },
  label: {
    fontSize: 18,
    color: '#0b1b33',
  },
});

export default App;
