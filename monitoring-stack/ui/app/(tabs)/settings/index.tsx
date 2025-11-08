import { sdk } from '@/components/utils/graphqlClient';
import { gql } from 'graphql-tag';
import React, { useEffect, useState } from 'react';
import { ActivityIndicator, Button, Platform, StyleSheet, Text, View } from 'react-native';

const VapidPublicKeyDocument = gql`
  query VapidPublicKey {
    vapidPublicKey
  }
`;

const SubscribeDocument = gql`
  mutation Subscribe($subscription: SubscriptionInput!) {
    subscribe(subscription: $subscription) {
      success
      message
    }
  }
`;

export default function SettingsScreen() {
  const [isSubscribed, setIsSubscribed] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [vapidPublicKey, setVapidPublicKey] = useState<string | null>(null);
  const [vapidKeyLoading, setVapidKeyLoading] = useState(true);
  const [vapidKeyError, setVapidKeyError] = useState<string | null>(null);

  useEffect(() => {
    if (Platform.OS === 'web' && 'serviceWorker' in navigator && 'PushManager' in window) {
      // Fetch VAPID public key
      const fetchVapidKey = async () => {
        setVapidKeyLoading(true);
        setVapidKeyError(null);
        try {
          const result = await sdk.VapidPublicKey();
          setVapidPublicKey(result.vapidPublicKey);
        } catch (err: any) {
          console.error('Error fetching VAPID public key:', err);
          setVapidKeyError(err.message || 'Failed to fetch VAPID public key.');
        } finally {
          setVapidKeyLoading(false);
        }
      };

      fetchVapidKey();

      // Check existing subscription
      navigator.serviceWorker.ready.then(registration => {
        registration.pushManager.getSubscription().then(subscription => {
          setIsSubscribed(!!subscription);
        });
      });
    }
  }, []);

  const subscribeToPushNotifications = async () => {
    if (Platform.OS !== 'web' || !('serviceWorker' in navigator) || !('PushManager' in window)) {
      setError('Push notifications are not supported in this environment.');
      return;
    }

    setLoading(true);
    setError(null);

    try {
      const permission = await Notification.requestPermission();
      if (permission !== 'granted') {
        setError('Notification permission denied.');
        setLoading(false);
        return;
      }

      if (!vapidPublicKey) {
        setError('VAPID Public Key not available.');
        setLoading(false);
        return;
      }

      const registration = await navigator.serviceWorker.ready;
      const subscription = await registration.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: vapidPublicKey,
      });

      // Send subscription to your backend
      const result = await sdk.Subscribe({
        subscription: JSON.parse(JSON.stringify(subscription))
      });

      if (result.subscribe.success) {
        setIsSubscribed(true);
        console.log('Push subscription successful:', result.subscribe.message);
      } else {
        setError(result.subscribe.message || 'Subscription failed.');
      }
    } catch (err: any) {
      console.error('Error subscribing to push notifications:', err);
      setError(err.message || 'Failed to subscribe to push notifications.');
    } finally {
      setLoading(false);
    }
  };

  return (
    <View style={styles.container}>
      <Text style={styles.title}>Settings</Text>
      {Platform.OS === 'web' && (
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Push Notifications</Text>
          {loading ? (
            <ActivityIndicator size="small" color="#0000ff" />
          ) : error ? (
            <Text style={styles.errorText}>{error}</Text>
          ) : vapidKeyLoading ? (
            <ActivityIndicator size="small" color="#0000ff" />
          ) : vapidKeyError ? (
            <Text style={styles.errorText}>{vapidKeyError}</Text>
          ) : isSubscribed ? (
            <Text>You are subscribed to push notifications.</Text>
          ) : (
            <Button title="Enable Push Notifications" onPress={subscribeToPushNotifications} disabled={!vapidPublicKey || loading} />
          )}
        </View>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#f0f0f0',
    padding: 20,
  },
  title: {
    fontSize: 24,
    fontWeight: 'bold',
    marginBottom: 20,
  },
  section: {
    backgroundColor: '#fff',
    padding: 15,
    borderRadius: 8,
    marginBottom: 15,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.2,
    shadowRadius: 1.41,
    elevation: 2,
  },
  sectionTitle: {
    fontSize: 18,
    fontWeight: '600',
    marginBottom: 10,
  },
  errorText: {
    color: 'red',
    marginTop: 10,
  },
});
