const copyButton = document.querySelector("[data-copy-loader]");
const loaderCode = document.querySelector("#loader-code");
const copyStatus = document.querySelector(".copy-status");
const imageViewer = document.querySelector("[data-image-viewer]");
const viewerImage = document.querySelector("[data-viewer-image]");
const viewerCaption = document.querySelector("[data-viewer-caption]");

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
  copyStatus.textContent = "Loader copied.";

  window.setTimeout(() => {
    copyButton.textContent = "Copy one-line loader";
    copyButton.classList.remove("is-copied");
    copyStatus.textContent = "";
  }, 1800);
}

copyButton.addEventListener("click", copyLoader);

for (const thumbnail of document.querySelectorAll("[data-gallery]")) {
  thumbnail.addEventListener("click", () => {
    const gallery = thumbnail.dataset.gallery;
    const mainImage = document.querySelector(`[data-gallery-main="${gallery}"]`);
    const mainButton = mainImage.closest("[data-open-image]");
    const siblings = document.querySelectorAll(`[data-gallery="${gallery}"]`);

    mainImage.src = thumbnail.dataset.src;
    mainImage.alt = thumbnail.dataset.alt;
    mainButton.setAttribute("aria-label", `Enlarge ${thumbnail.dataset.alt}`);

    for (const sibling of siblings) {
      const isActive = sibling === thumbnail;
      sibling.classList.toggle("is-active", isActive);
      sibling.setAttribute("aria-pressed", String(isActive));
    }
  });
}

for (const trigger of document.querySelectorAll("[data-open-image]")) {
  trigger.addEventListener("click", () => {
    const image = trigger.querySelector(".game-image");
    viewerImage.src = image.src;
    viewerImage.alt = image.alt;
    viewerCaption.textContent = image.alt;
    imageViewer.showModal();
  });
}

document.querySelector("[data-close-viewer]").addEventListener("click", () => {
  imageViewer.close();
});

imageViewer.addEventListener("click", (event) => {
  if (event.target === imageViewer) {
    imageViewer.close();
  }
});
