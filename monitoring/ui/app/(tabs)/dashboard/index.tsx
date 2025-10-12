import ReportsSection from '@/components/ReportsSection';
import React from 'react';
import { StyleSheet, Text, View } from 'react-native';

export default function DashboardScreen() {
  return (
    <View style={styles.container}>
      <Text style={styles.title}>Dashboard Screen</Text>
      <ReportsSection />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
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
