self.addEventListener('install', (event) => {
  console.log('Service Worker installing.');
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  console.log('Service Worker activating.');
  event.waitUntil(clients.claim());
});

self.addEventListener('push', (event) => {
  const options = {
    body: event.data ? event.data.text() : 'Default push message',
    icon: 'assets/images/icon.png', // Use an existing icon
    vibrate: [100, 50, 100],
    data: {
      dateOfArrival: Date.now(),
      primaryKey: '1',
    },
    actions: [
      {
        action: 'explore',
        title: 'Explore this new content',
        icon: 'assets/images/icon.png',
      },
      {
        action: 'close',
        title: 'Close the notification',
        icon: 'assets/images/icon.png',
      },
    ],
  };

  event.waitUntil(
    self.registration.showNotification('Test Notification', options)
  );
});

self.addEventListener('notificationclick', (event) => {
  console.log('[Service Worker] Notification click Received.');

  event.notification.close();

  if (event.action === 'explore') {
    clients.openWindow('https://example.com'); // Replace with your app's URL
  }
});

self.addEventListener('message', (event) => {
  if (event.data && event.data.type === 'DISPLAY_NOTIFICATION') {
    const { title, body } = event.data;
    self.registration.showNotification(title, {
      body: body,
      icon: 'assets/images/icon.png',
      vibrate: [100, 50, 100],
    });
  }
});
