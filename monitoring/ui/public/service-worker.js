self.addEventListener('install', async () => {
  console.log('Service worker installed');
  self.skipWaiting();
});

self.addEventListener('activate', async () => {
  console.log('Service worker activated');
});

self.addEventListener('push', event => {
  const data = event.data.json();
  console.log('Push received:', data);

  const title = data.title || 'Nuage Cluster Monitoring';
  const options = {
    body: data.body || 'You have a new notification.',
    icon: '/assets/images/icon.png', // Assuming an icon exists here
    badge: '/assets/images/favicon.png', // Assuming a badge icon exists here
  };

  event.waitUntil(self.registration.showNotification(title, options));
});

self.addEventListener('notificationclick', event => {
  event.notification.close();
  // You can add logic here to open a specific URL when the notification is clicked
  // event.waitUntil(clients.openWindow('/'));
});
