import { createApp } from 'vue';
import App from './App.vue';
import './style.css';
// Retire only Sentra's legacy service worker. Native owns module versioning.
if ('serviceWorker' in navigator) {
  void navigator.serviceWorker
    .getRegistrations()
    .then(async (registrations) => {
      const scope = new URL('./', location.href).href;
      for (const registration of registrations)
        if (registration.scope === scope) await registration.unregister();
    })
    .catch(() => {});
}
createApp(App).mount('#app');
