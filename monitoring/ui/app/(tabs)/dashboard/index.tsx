import ReportsSection from '@/components/ReportsSection';
import { StyleSheet } from 'react-native'; // Import Button and Platform
import { SafeAreaView } from "react-native-safe-area-context";

export default function DashboardScreen() {
  return (
    <SafeAreaView style={styles.container}>
      <ReportsSection />
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    // Removed justifyContent: 'center' and alignItems: 'center' to allow content to take full width and flow naturally
    backgroundColor: '#f0f0f0',
  },
});
