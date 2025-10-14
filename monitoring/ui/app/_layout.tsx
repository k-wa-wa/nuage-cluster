import { Stack } from 'expo-router';

export default function RootLayout() {
  return (
    <Stack>
      {/* This screen group will render the NativeTabs defined in app/(tabs)/_layout.tsx */}
      <Stack.Screen name="(tabs)" options={{ headerShown: false }} />
      {/* This screen will include the reports stack defined in app/reports/_layout.tsx */}
      <Stack.Screen name="reports" options={{ headerShown: false }} />
      {/* You can add other global screens here if needed */}
    </Stack>
  );
}
