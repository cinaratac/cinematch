(function () {
  const header = document.getElementById("siteHeader");
  const menuButton = document.getElementById("menuButton");
  const siteNav = document.getElementById("siteNav");
  const currentYear = document.getElementById("currentYear");

  if (window.location.search.includes("id=")) {
    window.location.replace(
      "https://play.google.com/store/apps/details?id=com.kozmosoft.cinematch&hl=tr"
    );
    return;
  }

  function syncHeader() {
    if (header) header.classList.toggle("scrolled", window.scrollY > 24);
  }

  function closeMenu() {
    if (!menuButton || !siteNav) return;
    menuButton.setAttribute("aria-expanded", "false");
    menuButton.setAttribute("aria-label", "Menüyü aç");
    siteNav.classList.remove("open");
    document.body.classList.remove("menu-open");
  }

  if (menuButton && siteNav) {
    menuButton.addEventListener("click", () => {
      const isOpen = menuButton.getAttribute("aria-expanded") === "true";
      menuButton.setAttribute("aria-expanded", String(!isOpen));
      menuButton.setAttribute("aria-label", isOpen ? "Menüyü aç" : "Menüyü kapat");
      siteNav.classList.toggle("open", !isOpen);
      document.body.classList.toggle("menu-open", !isOpen);
    });

    siteNav.querySelectorAll("a").forEach((link) => {
      link.addEventListener("click", closeMenu);
    });
  }

  window.addEventListener("scroll", syncHeader, { passive: true });
  syncHeader();

  if (currentYear) currentYear.textContent = String(new Date().getFullYear());

})();
