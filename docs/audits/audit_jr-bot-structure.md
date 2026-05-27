# JR-Bot Structure Audit Handbook

Status: Active  
Handbook Version: 1.0  
Script Version Reference: 0.1.6  
Project: JR-Bot / OPSCON  
Last Updated: 2026-05-27  

---

## 1. Purpose

`audit_jr-bot-structure.sh` ist das zentrale Structure-Audit-Script für JR-Bot Nodes.

Das Script prüft lesend, wie ein JR-Bot auf einem Raspberry Pi oder vergleichbaren Linux-Node installiert ist. Es sammelt technische Informationen über Host, Netzwerk, Storage, Python-Umgebung, Bot-Verzeichnisstruktur, Runtime-Dateien, Systemd-Integration und bekannte Wartungsscripte.

Das Ziel ist nicht, den Bot zu reparieren oder automatisch umzubauen. Das Ziel ist eine reproduzierbare, sichere und maschinenlesbare Bestandsaufnahme.

Das Script ist besonders wichtig für:

- Vergleich von alten und neuen JR-Bot Installationen
- Erkennung von Legacy-, Hybrid- und Zielstrukturen
- Vorbereitung von Migrationen
- OPSCON Monitoring
- spätere JR-Agent Analyse
- One-Liner Installer Validierung
- Nachvollziehbarkeit von Strukturabweichungen

---

## 2. Rolle im JR-Bot / OPSCON System

Das Structure-Audit ist eines von mehreren Diagnose- und Reporting-Werkzeugen.

Es beantwortet primär die Frage:

> Wie ist dieser JR-Bot aktuell aufgebaut?

Es ist damit kein Live-Health-Check und kein Boot-Report.

### Abgrenzung zu anderen Scripts

| Script | Zweck |
|---|---|
| `audit_jr-bot-structure.sh` | Prüft Struktur, Dateien, Verzeichnisse, Python, Systemd, Bot-Profil |
| `audit_jr-bot-network-health.sh` | Prüft Netzwerkdienste, WLAN, DHCP, Routen, DNS, Connectivity |
| `jrbot_boot_report.sh` | Sammelt Boot-Zustand kurz nach Neustart und meldet ihn an OPSCON |
| `reboot.sh` | Führt kontrollierten Reboot über Maintenance-Job aus |

Das Structure-Audit ist daher die richtige Wahl, wenn unklar ist:

- Welche Ordner existieren?
- Welche Runtime-Struktur liegt vor?
- Ist der Bot legacy, template oder hybrid?
- Fehlen Wartungsscripte?
- Welche systemd-Units sind vorhanden?
- Wo liegen Audit-Scripte aktuell?
- Gibt es `.env` oder `config.ini`?
- Ist die Python-venv vorhanden und funktionsfähig?

---

## 3. Sicherheitsprinzip

Das Script ist bewusst read-only.

Es führt keine Änderungen am Zielsystem durch.

### Sicherheitsregeln

- Keine Secrets werden ausgegeben.
- Keine Tokenwerte werden aus `.env` oder `config.ini` ausgelesen.
- Es wird nur geprüft, ob bestimmte Keys vorhanden sind.
- Config-Inhalte werden nicht vollständig übertragen.
- Das Script verändert keine Dateien.
- Das Script startet oder stoppt keine Dienste.
- Der Upload an OPSCON erfolgt nur optional.
- Lokale temporäre JSON-Dateien werden nach erfolgreichem Upload entfernt, außer `--keep-local` oder `--output` wurde gesetzt.

### Secrets

Folgende Werte werden nur auf Key-Existenz geprüft:

- `SERVER_BASE`
- `SERVER_TOKEN`
- `PING_TOKEN`
- `BOT_NAME`
- `PROJECT_NAME`
- `INSTANCE_NAME`

Der Wert selbst wird nicht in die Audit-JSON geschrieben.

---

## 4. Typische Aufrufe

### Lokaler Audit ohne Upload

```bash
./audit_jr-bot-structure.sh \
  --instance trx \
  --path /opt/bots/trx
