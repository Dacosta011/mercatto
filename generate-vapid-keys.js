const webPush = require("web-push");
const keys = webPush.generateVAPIDKeys();
console.log("Add these to your .env.local:\n");
console.log(`NEXT_PUBLIC_VAPID_PUBLIC_KEY=${keys.publicKey}`);
console.log(`VAPID_PRIVATE_KEY=${keys.privateKey}`);
console.log(`VAPID_EMAIL=mailto:your-email@example.com`);
console.log(`CRON_SECRET=your-secret-here`);
