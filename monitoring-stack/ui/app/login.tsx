import { ThemedText } from '@/components/themed-text';
import { ThemedView } from '@/components/themed-view';
import { sdk } from '@/components/utils/graphqlClient'; // sdkをインポート
import AsyncStorage from '@react-native-async-storage/async-storage'; // AsyncStorageをインポート
import { router } from 'expo-router';
import { gql } from 'graphql-tag'; // gqlをインポート
import React, { useState } from 'react';
import { Alert, Button, StyleSheet, Text, TextInput } from 'react-native';

const LoginDocument = gql`
  mutation Login($username: String!, $password: String!) {
    login(username: $username, password: $password) {
      token
      expiresIn
    }
  }
`;

export default function LoginScreen() {
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const handleLogin = async () => {
    setLoading(true);
    setError(null);
    try {
      const data = await sdk.Login({ username, password });
      if (data.login.token) {
        await AsyncStorage.setItem('userToken', data.login.token); // Save token
        Alert.alert('Login Successful', 'Redirecting to dashboard.');
        router.replace('/(tabs)/dashboard'); // Navigate to dashboard and remove login screen from history
      }
    } catch (e: any) {
      setError(e.message || 'An unknown error occurred.');
      Alert.alert('Login Failed', e.message || 'An unknown error occurred.');
    } finally {
      setLoading(false);
    }
  };

  return (
    <ThemedView style={styles.container}>
      <ThemedText type="title" style={styles.title}>Login</ThemedText>
      <TextInput
        style={styles.input}
        placeholder="Username"
        value={username}
        onChangeText={setUsername}
        autoCapitalize="none"
      />
      <TextInput
        style={styles.input}
        placeholder="Password"
        value={password}
        onChangeText={setPassword}
        secureTextEntry
      />
      {error && <Text style={styles.errorText}>{error}</Text>}
      <Button title={loading ? 'Logging in...' : 'Login'} onPress={handleLogin} disabled={loading} />
    </ThemedView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    paddingHorizontal: 20,
    backgroundColor: '#f0f2f5', // Light background for a clean look
  },
  title: {
    fontSize: 32,
    fontWeight: 'bold',
    marginBottom: 40,
    color: '#333',
  },
  input: {
    width: '100%',
    padding: 15,
    marginVertical: 10,
    backgroundColor: '#fff',
    borderRadius: 10,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.1,
    shadowRadius: 4,
    elevation: 3,
    fontSize: 16,
    color: '#333',
  },
  errorText: {
    color: '#e74c3c',
    marginTop: 10,
    marginBottom: 20,
    textAlign: 'center',
    fontSize: 14,
  },
});
