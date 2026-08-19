(() => {
  const initialSettings = window.__NEXT_DATA__?.props?.pageProps?.initialSettings;

  // Homepage's prebuilt page contains empty settings until its runtime cache is
  // regenerated. Avoid touching pages that already contain runtime settings.
  if (!initialSettings || Object.keys(initialSettings).length > 0) {
    return;
  }

  const revalidateRuntimeSettings = async () => {
    try {
      const hashResponse = await fetch("/api/hash", { credentials: "same-origin" });
      if (!hashResponse.ok || hashResponse.redirected) {
        throw new Error(`config hash request failed with status ${hashResponse.status}`);
      }

      const { hash } = await hashResponse.json();
      if (!hash) {
        throw new Error("config hash response did not include a hash");
      }

      const marker = `homepage-runtime-settings-revalidated:${hash}`;
      if (sessionStorage.getItem(marker)) {
        return;
      }

      // Set the marker before requesting regeneration so an unexpected empty
      // response after reload cannot create an infinite reload loop.
      sessionStorage.setItem(marker, "true");

      const revalidateResponse = await fetch("/api/revalidate", { credentials: "same-origin" });
      const result = revalidateResponse.redirected ? null : await revalidateResponse.json().catch(() => null);
      if (!revalidateResponse.ok || result?.revalidated !== true) {
        sessionStorage.removeItem(marker);
        throw new Error(`runtime settings revalidation failed with status ${revalidateResponse.status}`);
      }

      window.location.reload();
    } catch (error) {
      console.error("Unable to load Homepage runtime settings", error);
    }
  };

  void revalidateRuntimeSettings();
})();
