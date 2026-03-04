const body = document.body;
const header = document.getElementById("siteHeader");
const nav = document.getElementById("siteNav");
const menuToggle = document.getElementById("menuToggle");
const openSearch = document.getElementById("openSearch");
const closeSearch = document.getElementById("closeSearch");
const searchDrawer = document.getElementById("searchDrawer");
const yearEl = document.getElementById("year");

function syncHeaderState() {
  if (window.scrollY > 48) {
    header.classList.add("scrolled");
  } else {
    header.classList.remove("scrolled");
  }
}

function closeNav() {
  body.classList.remove("nav-open");
  menuToggle.setAttribute("aria-expanded", "false");
}

menuToggle.addEventListener("click", () => {
  const isOpen = body.classList.toggle("nav-open");
  menuToggle.setAttribute("aria-expanded", String(isOpen));
});

nav.querySelectorAll("a").forEach((link) => {
  link.addEventListener("click", closeNav);
});

openSearch.addEventListener("click", () => {
  searchDrawer.hidden = false;
  const input = searchDrawer.querySelector("input");
  if (input) {
    input.focus();
  }
});

closeSearch.addEventListener("click", () => {
  searchDrawer.hidden = true;
});

window.addEventListener("keydown", (event) => {
  if (event.key === "Escape") {
    closeNav();
    searchDrawer.hidden = true;
  }
});

window.addEventListener("scroll", syncHeaderState, { passive: true });
syncHeaderState();

yearEl.textContent = new Date().getFullYear();
