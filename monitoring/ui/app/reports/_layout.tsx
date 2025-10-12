import { Stack } from 'expo-router';

export default function ReportLayout() {
  return (
    <Stack>
      <Stack.Screen name="[id]" options={{ headerShown: true, title: 'Report Details' }} />
    </Stack>
  );
}
