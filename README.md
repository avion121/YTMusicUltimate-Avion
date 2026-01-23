# YTMusicUltimate

## What's New in YTMusicUltimate-Avion

### Three New Files Added

**AutoClearCache.xm**
- Clears app cache when the app starts  
- Runs in the background  
- Helps free up storage  

**NewFeatures.xm**
- **Always High Quality Audio:** Forces high quality even without Premium  
- **Skip Disliked Songs:** Automatically skips songs you've disliked  
- **Discord Rich Presence:** Saves what you're playing so Discord can show it (requires external setup)  

**BugFixes.xm (489 lines)**
- Recap not opening: Fixed  
- Audio glitches when switching tracks: Fixed buffer issues  
- Content warning black screen: Improved handling  
- Crashes on non-standard video sizes: Added safety checks  
- Music video vs audio preference: Option to prefer audio-only  
- Ads still showing during AirPlay/shuffle: Improved ad blocking  

### Improvements to Existing Features

**SponsorBlock**
- Added support for podcasts: skips sponsors, intros, outros in podcasts  
- Better error handling  

**Settings Menu**
- Added 3 new player options:
  - Always high quality audio  
  - Skip disliked songs  
  - Prefer audio-only version  
- Added SponsorBlock for podcasts toggle  
- Added Import/Export settings (backup/restore)  
- Added Discord RPC toggle  

---

<p align="center">
  <img src="https://user-images.githubusercontent.com/38832025/235781424-06d81647-b3db-4d9b-94dc-cd65cdf09145.png" />
</p>    

<p align="center">
  <img src="https://user-images.githubusercontent.com/38832025/235781207-6d1ad44e-0c32-4aec-9c75-cb928ca8a0d3.png" />
</p>

<p align="center">
  The best tweak for YouTube Music on iOS.
</p>

---

## Download Links

### Jailbreak
Add [https://ginsu.dev/repo](https://ginsu.dev/repo) to your favorite installer and download the latest version from there, or from the [Releases](https://github.com/ginsudev/YTMusicUltimate/releases) page.  

*(arm.deb version for Rootful and arm64.deb version for Rootless devices)*

### Sideloading
We no longer provide a sideloading IPA, but you can build one yourself. Keep reading:

---

## How to Build a YTMusicUltimate IPA Yourself Using GitHub Actions

If this is your first time here, start from step 1. If you’ve built a YTMU IPA before, skip steps 1 and 2 and click the "Sync fork" button to get the latest version of the tweak, then continue with step 3.

1. Fork this repository using the fork button on the top right.  
2. On your forked repository, go to **Repository Settings > Actions**, enable **Read and Write permissions**.  
3. Go to the **Actions** tab on your forked repo, click **Build and Release YTMusicUltimate** on the left, then click **Run workflow**.  
4. Upload a decrypted YTMusic `.ipa` file to a file provider (filebin.net or Dropbox recommended) and paste the URL in the necessary field, then click **Run workflow**.  
5. Wait for the build to finish. You can download the tweaked IPA from the **Releases** section of your forked repo.  
   *(If you can’t find the releases section, add `/releases` to your forked repo URL, e.g., `https://github.com/YOURUSERNAME/YTMusicUltimate/releases`.)*

---

### IPA Building Troubleshooting

99.9% of build failures are caused by an incorrect IPA URL. Make sure you provide a **decrypted `.ipa` file**. Other formats will not work.  

If the GitHub Action succeeds but you can’t find the result, manually go to `/releases` in your forked repo URL.

---

## How to Build the Package Yourself on Your Device

1. Install [Theos](https://theos.dev/docs/installation).  
2. Clone this repository using [Git](https://docs.github.com/en/repositories/creating-and-managing-repositories/cloning-a-repository).  
3. In your YTMusicUltimate folder, run:

   - `make clean package` → builds deb for rootful devices  
   - `make clean package ROOTLESS=1` → builds deb for rootless devices  
   - `make clean package SIDELOADING=1` → builds deb for injecting into IPA  

To learn how to inject tweaks into an IPA, visit [Azule](https://github.com/Al4ise/Azule).

---

Made with ❤ by Ginsu and Dayanch96
