/*
 * The kit gallery: every component in every state, for review by eye and
 * for the snapshot run. The query string picks the theme (`?theme=cozy`),
 * the language (`?lang=ja`, which also sets the reading direction), `still`
 * for a render with no motion (loaders at their first frame, marquees at
 * rest or `?scrolled=0.5` of the way), and `reduce` to force Reduce Motion.
 */

import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { loadLanguage } from "../i18n/strings";
import { DEFAULT_THEME_ID, findTheme } from "../core/themes/themeCatalog";
import { KitProvider } from "../ui/kit/context";
import { applyKitTheme } from "../ui/kit/tokens";
import { Gallery } from "./Gallery";
import "../ui/kit/kit.css";
import "./gallery.css";

const query = new URLSearchParams(window.location.search);
const themeId = findTheme(query.get("theme") ?? "")?.id ?? DEFAULT_THEME_ID;
const still = query.has("still");
const reduce = query.has("reduce");
const scrolledParam = query.get("scrolled");
const scrolled = scrolledParam === null ? undefined : Number(scrolledParam);

applyKitTheme(document.documentElement, themeId);
document.documentElement.classList.add("kit-root");

const override = query.get("lang");
const { language, direction } = await loadLanguage(override ? [override] : navigator.languages);
document.documentElement.lang = language;
document.documentElement.dir = direction;
document.title = `Tabbi kit gallery: ${themeId}, ${language}`;

const root = document.getElementById("root");
if (!root) throw new Error("gallery.html has no #root");

createRoot(root).render(
  <StrictMode>
    <KitProvider themeId={themeId} still={still} reduceMotion={reduce ? true : undefined} marqueeScrolled={scrolled}>
      <Gallery themeId={themeId} language={language} />
    </KitProvider>
  </StrictMode>,
);
