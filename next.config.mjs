/** @type {import('next').NextConfig} */

// Where the Android app is actually hosted.
//
// The APK is 60 MB, and for a while it lived in public/ - which meant every
// deployment carried its own copy, and a new build every time the app changed.
// Thirty or so releases later that was six gigabytes of deployment storage out
// of a ten gigabyte allowance, for one file that never needed to be there.
//
// It lives on GitHub Releases now, which is built for binaries and does not
// charge the site for them. Point this at the newest release when the app is
// updated; nothing else needs to change.
const APK_URL =
  'https://github.com/Senaaravichandran/OD/releases/download/v3.4.3/smvec-od.apk';

const nextConfig = {
  async redirects() {
    return [
      {
        // The address on the posters, in the QR codes and in every phone that
        // has already installed the app. It keeps working and always will -
        // which is the only reason the file could be moved at all.
        source: '/downloads/smvec-od.apk',
        destination: APK_URL,
        // Temporary on purpose: a permanent redirect is cached by browsers
        // for good, and this target changes with every release.
        permanent: false,
      },
    ];
  },
};

export default nextConfig;
