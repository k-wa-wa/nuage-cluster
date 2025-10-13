import ReportsSection from '@/components/ReportsSection';
import React, { useEffect } from 'react'; // Import useEffect
import { Button, Platform, StyleSheet, Text, View } from 'react-native'; // Import Button and Platform

export default function DashboardScreen() {
  const requestNotificationPermission = async () => {
    if (Platform.OS === 'web' && 'Notification' in window) {
      const permission = await Notification.requestPermission();
      console.log('Notification permission:', permission);
      return permission === 'granted';
    }
    return false;
  };

  const sendTestNotification = async () => {
    if (Platform.OS === 'web' && 'serviceWorker' in navigator && navigator.serviceWorker.controller) {
      const permissionGranted = await requestNotificationPermission();
      if (permissionGranted) {
        navigator.serviceWorker.controller.postMessage({
          type: 'DISPLAY_NOTIFICATION',
          title: 'Manual Test Notification',
          body: 'This is a notification triggered manually.',
        });
        console.log('Manual test notification sent to service worker.');
      } else {
        console.warn('Notification permission not granted for manual test.');
      }
    } else {
      console.warn('Service Worker not available or not controlled for manual test.');
    }
  };

  useEffect(() => {
    if (Platform.OS === 'web' && 'serviceWorker' in navigator && navigator.serviceWorker.controller) {
      const setupIntervalNotification = async () => {
        const permissionGranted = await requestNotificationPermission();
        if (permissionGranted) {
          const intervalId = setInterval(() => {
            navigator.serviceWorker.controller.postMessage({
              type: 'DISPLAY_NOTIFICATION',
              title: 'Interval Test Notification',
              body: `This is an interval notification at ${new Date().toLocaleTimeString()}`,
            });
            console.log('Interval test notification sent to service worker.');
          }, 60 * 1000); // Every 1 minute

          return () => clearInterval(intervalId);
        }
      };
      setupIntervalNotification();
    }
  }, []);

  return (
    <View style={styles.container}>
      <Text style={styles.title}>Dashboard Screen</Text>
      <Button title="Request Notification Permission" onPress={requestNotificationPermission} />
      <Button title="Send Manual Test Notification" onPress={sendTestNotification} />
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
  title: {
    fontSize: 32,
    fontWeight: 'bold',
    marginBottom: 20,
  },
  link: {
    backgroundColor: '#007bff',
    paddingVertical: 12,
    paddingHorizontal: 24,
    borderRadius: 8,
  },
  linkText: {
    color: '#fff',
    fontSize: 18,
    fontWeight: 'bold',
  },
});
