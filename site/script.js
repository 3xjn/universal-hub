const copyButton = document.querySelector("[data-copy-loader]");
const loaderCode = document.querySelector("#loader-code");
const copyStatus = document.querySelector(".copy-status");

async function copyLoader() {
  const source = loaderCode.textContent.trim();

  try {
    await navigator.clipboard.writeText(source);
  } catch {
    const input = document.createElement("textarea");
    input.value = source;
    input.setAttribute("readonly", "");
    input.style.position = "fixed";
    input.style.opacity = "0";
    document.body.append(input);
    input.select();
    document.execCommand("copy");
    input.remove();
  }

  copyButton.textContent = "Copied";
  copyButton.classList.add("is-copied");
  copyStatus.textContent = "Loader copied to clipboard.";

  window.setTimeout(() => {
    copyButton.textContent = "Copy loader";
    copyButton.classList.remove("is-copied");
    copyStatus.textContent = "";
  }, 1800);
}

copyButton.addEventListener("click", copyLoader);

for (const thumbnail of document.querySelectorAll("[data-gallery]")) {
  thumbnail.addEventListener("click", () => {
    const gallery = thumbnail.dataset.gallery;
    const mainImage = document.querySelector(`[data-gallery-main="${gallery}"]`);
    const siblings = document.querySelectorAll(`[data-gallery="${gallery}"]`);

    mainImage.src = thumbnail.dataset.src;
    mainImage.alt = thumbnail.dataset.alt;

    for (const sibling of siblings) {
      const isActive = sibling === thumbnail;
      sibling.classList.toggle("is-active", isActive);
      sibling.setAttribute("aria-pressed", String(isActive));
    }
  });
}

document.querySelector("[data-year]").textContent = new Date().getFullYear();
