import React from 'react';
import { ActivityIndicator, StyleSheet, View } from 'react-native';
import { ThemedView } from '@/components/themed-view';
import { ThemedText } from '@/components/themed-text';

export default function LoadingScreen() {
  return (
    <ThemedView style={styles.container}>
      <ActivityIndicator size="large" color="#0000ff" />
      <ThemedText style={styles.text}>読み込み中...</ThemedText>
    </ThemedView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
  text: {
    marginTop: 10,
    fontSize: 16,
  },
});
