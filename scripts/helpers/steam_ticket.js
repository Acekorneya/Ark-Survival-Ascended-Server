#!/usr/bin/env node

const SteamUser = require("steam-user");

const client = new SteamUser();
const appId = parseInt(process.env.STEAM_APP_ID || "2399830", 10);
const minTicketBytes = parseInt(process.env.STEAM_SESSION_TICKET_MIN_BYTES || "32", 10);
const ticketRequestDelayMs = Math.max(parseInt(process.env.STEAM_TICKET_REQUEST_DELAY_MS || "3000", 10), 0);
const debugEnabled = process.env.STEAM_TICKET_DEBUG === "1";

function debug(message) {
  if (debugEnabled) {
    console.error(message);
  }
}

function formatSteamError(err) {
  const rawMessage = err && err.message ? String(err.message) : String(err || "Unknown Steam error");

  if (rawMessage.includes("RateLimitExceeded")) {
    return "Steam error: RateLimitExceeded. Steam is temporarily rate-limiting this account. Wait a few minutes and try -status again.";
  }

  return `Steam error: ${rawMessage}`;
}

function extractSessionTicket(sessionTicket) {
  if (Buffer.isBuffer(sessionTicket)) {
    return sessionTicket;
  }

  if (sessionTicket && Buffer.isBuffer(sessionTicket.sessionTicket)) {
    return sessionTicket.sessionTicket;
  }

  if (sessionTicket && Buffer.isBuffer(sessionTicket.ticket)) {
    return sessionTicket.ticket;
  }

  return null;
}

function getTicket(callback) {
  if (typeof client.createAuthSessionTicket !== "function") {
    callback(new Error("Steam createAuthSessionTicket API is not available in this steam-user build"));
    return;
  }

  client.createAuthSessionTicket(appId, (err, sessionTicket) => {
    if (err) {
      callback(err);
      return;
    }

    const ticket = extractSessionTicket(sessionTicket);
    if (!ticket) {
      callback(new Error("Steam session ticket was returned in an unexpected format"));
      return;
    }

    if (ticket.length < minTicketBytes) {
      callback(new Error(`Steam session ticket is unexpectedly short (${ticket.length} bytes)`));
      return;
    }

    callback(null, ticket);
  });
}

async function main() {
  const logOnOptions = {
    accountName: process.env.STEAM_USERNAME,
    password: process.env.STEAM_PASSWORD,
  };

  client.logOn(logOnOptions);

  client.on("steamGuard", (domain, callback) => {
    const guardCode = process.env.STEAM_GUARD_CODE;
    if (guardCode) {
      debug(`Steam Guard: using STEAM_GUARD_CODE for ${domain || "mobile authenticator"}`);
      callback(guardCode);
      return;
    }
    console.error(`STEAM_GUARD_REQUIRED:${domain || "mobile authenticator"}`);
    console.error(
      `Steam Guard required (${domain || "mobile authenticator"}). ` +
      `Enter the current 5-digit code from your Steam app when prompted.`
    );
    process.exit(1);
  });

  client.on("loggedOn", () => {
    debug(`Steam logged on for app ${appId}`);
    client.gamesPlayed(appId, true);
    setTimeout(() => {
      getTicket((err, ticket) => {
        if (err) {
          console.error("Failed to get auth ticket:", err.message);
          process.exit(1);
        }

        debug(`Steam session ticket length: ${ticket.length} bytes`);
        if (typeof SteamUser.parseAppTicket === "function") {
          try {
            const parsedTicket = SteamUser.parseAppTicket(ticket);
            if (parsedTicket && parsedTicket.authTicket) {
              debug(`Parsed auth ticket length: ${parsedTicket.authTicket.length} bytes`);
            }
          } catch (err) {
            debug(`Steam ticket parse failed: ${err.message}`);
          }
        }

        process.stdout.write(ticket.toString("hex").toUpperCase());
        client.logOff();
        setTimeout(() => process.exit(0), 2000);
      });
    }, ticketRequestDelayMs);
  });

  client.on("error", (err) => {
    console.error(formatSteamError(err));
    process.exit(1);
  });
}

main().catch((err) => {
  console.error(err.message || err);
  process.exit(1);
});
