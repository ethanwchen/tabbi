import { describe, expect, it } from "vitest";
import { classifyMeetingURL, detectMeetingLink, linksInText, meetingProviderName } from "../../../src/core/planner/meetingLink";

describe("meeting links", () => {
  it("recognizes Zoom, Meet and Teams join links only", () => {
    expect(classifyMeetingURL("https://us02web.zoom.us/j/81234567890?pwd=abc")?.provider).toBe("zoom");
    expect(classifyMeetingURL("https://zoom.us/my/alex")?.provider).toBe("zoom");
    expect(classifyMeetingURL("https://zoom.us/pricing")).toBeUndefined();
    expect(classifyMeetingURL("https://meet.google.com/abc-defg-hij")?.provider).toBe("googleMeet");
    expect(classifyMeetingURL("https://meet.google.com/")).toBeUndefined();
    expect(classifyMeetingURL("https://meet.google.com/lookup/xyz")?.provider).toBe("googleMeet");
    expect(classifyMeetingURL("https://teams.microsoft.com/l/meetup-join/19%3ameeting_x%40thread.v2/0")?.provider).toBe("teams");
    expect(classifyMeetingURL("https://teams.live.com/meet/9876")?.provider).toBe("teams");
    expect(classifyMeetingURL("https://teams.microsoft.com/")).toBeUndefined();
    expect(classifyMeetingURL("ftp://zoom.us/j/1")).toBeUndefined();
    expect(classifyMeetingURL("not a url")).toBeUndefined();
  });

  it("upgrades plain http to https", () => {
    expect(classifyMeetingURL("http://zoom.us/j/5551234567")?.url).toBe("https://zoom.us/j/5551234567");
  });

  it("checks the URL field, then the location, then the notes", () => {
    const notes = "Agenda: https://docs.example.com/doc\nJoin: <https://meet.google.com/abc-defg-hij>.\nDial-in +1 555";
    expect(detectMeetingLink({ notes })).toEqual({ provider: "googleMeet", url: "https://meet.google.com/abc-defg-hij" });
    expect(
      detectMeetingLink({ url: "https://zoom.us/j/1", location: "https://meet.google.com/abc-defg-hij", notes })?.provider,
    ).toBe("zoom");
    expect(detectMeetingLink({ location: "Room 4", notes: "nothing here" })).toBeUndefined();
  });

  it("finds bare hosts and trims trailing punctuation the way invites write them", () => {
    expect(linksInText("Join at meet.google.com/abc-defg-hij, see you")).toEqual(["http://meet.google.com/abc-defg-hij"]);
    expect(linksInText("(https://zoom.us/j/123)")).toEqual(["https://zoom.us/j/123"]);
    expect(linksInText('<a href="https://zoom.us/j/9">join</a>')).toEqual(["https://zoom.us/j/9"]);
  });

  it("names providers for tooltips", () => {
    expect(meetingProviderName("googleMeet")).toBe("Google Meet");
  });
});
