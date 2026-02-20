# View impressions & who visited

## Option 1: Google Analytics 4 (recommended, free)

**What you get:** Page views, unique visitors, country/city, device, browser, referrer (where they came from).  
**“Who”:** Anonymized (no names/emails). You see “X visitors from USA” not “John from NYC.”  
**Who you know:** Only people who submit the waitlist form (you already store those in the API).

### Setup (one-time)

1. Go to [analytics.google.com](https://analytics.google.com) and sign in.
2. **Admin** (gear) → **Create property** → name it “Savvy” → set timezone/currency → **Create**.
3. **Data streams** → **Add stream** → **Web**.
   - URL: `https://sara3.github.io/savvy_landing`
   - Stream name: e.g. “Savvy landing”
   - **Create stream**.
4. Copy the **Measurement ID** (e.g. `G-ABC123XYZ`).
5. In `index.html`, find the two places that say `G-XXXXXXXXXX` and replace both with your Measurement ID.
6. Save, commit, and push. After deploy, GA4 will start counting visits (can take up to 24–48 hours for reports to fill).

### Where to see impressions

- **Reports** → **Engagement** → **Pages and screens**: page views (impressions).
- **Reports** → **Acquisition** → **User acquisition** / **Traffic acquisition**: where visitors came from.
- **Reports** → **Demographics**: country, city, device, etc. (all anonymized).

---

## Option 2: Backend page-view logging

If you want “who visited” stored in your own system (e.g. IP, time, referrer), you can add a small call from the frontend to your API when the page loads, and log that in your backend/DB. That still doesn’t give identity unless the user signs up. I can add a minimal “page view” endpoint and frontend ping if you want this.

---

## Summary

| What you want        | How to get it                          |
|----------------------|----------------------------------------|
| **Impressions/views**| GA4 (replace `G-XXXXXXXXXX` in index)  |
| **Who visited**      | GA4 = anonymized stats; “who” = signups (already in your API) |
