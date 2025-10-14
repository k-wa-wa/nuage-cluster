import ReportsSection from '@/components/ReportsSection';
import React from 'react'; // Import useEffect
import { StyleSheet, View } from 'react-native'; // Import Button and Platform

export default function DashboardScreen() {
  return (
    <View style={styles.container}>
      <ReportsSection />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    // Removed justifyContent: 'center' and alignItems: 'center' to allow content to take full width and flow naturally
    backgroundColor: '#f0f0f0',
  },
});
