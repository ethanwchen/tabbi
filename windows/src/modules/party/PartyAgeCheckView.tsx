/*
 * Port of PartyAgeCheckView: what Party shows before it talks to the server
 * (`PartyAgeCheck`): the month and year the user was born, asked once and
 * without hinting at the answer, beside links to the Terms and Privacy
 * Policy. Answered under 13, it says when Party opens instead, with no way
 * to answer again.
 */

import { useState } from "react";
import { tr } from "../../core/localization/tr";
import { birthYears, MINIMUM_AGE, monthNames, opensText } from "../../core/party/partyAgeCheck";
import { SupportContact } from "../../core/party/partyModeration";
import { Picker } from "../../ui/kit/Picker";
import { StatusMessage } from "../../ui/kit/StatusMessage";
import { Tooltip } from "../../ui/kit/Tooltip";
import { PartyPillButton, partyLocale } from "./PartyComponents";
import type { PartyStore } from "./partyStore";

export function PartyAgeCheckView({ store, tooYoungUntil }: { store: PartyStore; tooYoungUntil: number | undefined }) {
  if (tooYoungUntil !== undefined) {
    return (
      <StatusMessage
        symbol="hand.raised.fill"
        title={tr("Party isn't available yet")}
        message={tr("Party is for people %lld and older. It opens here in %@.", MINIMUM_AGE, opensText(tooYoungUntil, partyLocale(), store.timeZone()))}
      />
    );
  }
  return <PartyAgeQuestion store={store} />;
}

const NONE = "none";

/** "When were you born?" with a month and a year menu, both starting blank so no answer is suggested, and Continue once both are picked. */
function PartyAgeQuestion({ store }: { store: PartyStore }) {
  const [month, setMonth] = useState<string>(NONE);
  const [year, setYear] = useState<string>(NONE);
  const months = monthNames(partyLocale());
  const years = birthYears(store.now(), store.timeZone());
  const ready = month !== NONE && year !== NONE;
  return (
    <div className="party-age">
      <div className="party-age-words">
        <span className="kit-title">{tr("When were you born?")}</span>
        <span className="kit-body kit-secondary">{tr("Party asks once before you join. Your answer stays on this PC.")}</span>
      </div>
      <div className="party-age-row">
        <Picker
          items={[{ id: NONE, title: tr("Month") }, ...months.map((name, index) => ({ id: String(index + 1), title: name }))]}
          selected={month}
          onSelect={setMonth}
          label={tr("Month")}
          help={tr("The month you were born")}
          width={112}
          className="party-age-picker"
        />
        <Picker
          items={[{ id: NONE, title: tr("Year") }, ...years.map((value) => ({ id: String(value), title: String(value) }))]}
          selected={year}
          onSelect={setYear}
          label={tr("Year")}
          help={tr("The year you were born")}
          width={76}
          className="party-age-picker"
        />
        <PartyPillButton
          title={tr("Continue")}
          prominent={ready}
          help={ready ? tr("Join Party") : tr("Pick a month and a year first")}
          onClick={() => {
            if (ready) store.answerAge(Number(month), Number(year));
          }}
        />
      </div>
      <Tooltip text={tr("Opens on tabbinotch.com")}>
        <span className="kit-caption kit-tertiary party-agreement">
          <Agreement onOpen={(url) => store.openURL(url)} />
        </span>
      </Tooltip>
    </div>
  );
}

/** The links the user agrees to by joining: the catalog's Markdown sentence, with its two links made clickable. */
export function Agreement({ onOpen, signingIn = false }: { onOpen: (url: string) => void; signingIn?: boolean }) {
  const text = signingIn
    ? tr("By signing in you agree to the [Terms of Use](%@) and the [Privacy Policy](%@).", SupportContact.termsURL, SupportContact.privacyURL)
    : tr("By joining you agree to the [Terms of Use](%@) and the [Privacy Policy](%@).", SupportContact.termsURL, SupportContact.privacyURL);
  const parts = text.split(/(\[[^\]]+\]\([^)]+\))/);
  return (
    <>
      {parts.map((part, index) => {
        const link = /^\[([^\]]+)\]\(([^)]+)\)$/.exec(part);
        if (link === null) return <span key={index}>{part}</span>;
        const url = link[2] ?? "";
        return (
          <button key={index} type="button" className="party-link" onClick={() => onOpen(url)}>
            {link[1]}
          </button>
        );
      })}
    </>
  );
}
