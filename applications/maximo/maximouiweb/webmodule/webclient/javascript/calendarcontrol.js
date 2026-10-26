/*
 * calendarcontrol.js
 * ------------------
 * Client controller for the reusable MAS <calendarcontrol>.
 *
 * Each rendered instance exposes its data on
 *     window.__MASCAL_DATA["<ctrlId>"]
 * (written inline by calendarcontrol.jsp) and the matching DOM root is
 *     <div class="mascal-root" data-mascal="<ctrlId>">.
 *
 * One FullCalendar instance is created per control root. The legend
 * (two tabs: Primary filter + custom Secondary filter) is rendered entirely in
 * JS from the same data, and toggling a checkbox hides/shows events
 * instantly without a server round-trip.
 *
 * When a group-by attribute is configured for a filter tab, that tab is
 * rendered as a two-level tree: the group-by values at the root and the
 * filter values found under each group as children. Both levels can be
 * toggled independently.
 *
 * Clicking an event opens a scrollable dialog listing the visible events
 * for that day, including events hidden by the calendar's overflow limit.
 */
(function (global) {
    "use strict";

    var MASCAL = global.MASCAL = global.MASCAL || {};

    /* View name -> FullCalendar view key (FC v6) */
    var VIEW_MAP = {
        month: "dayGridMonth",
        week:  "timeGridWeek",
        day:   "timeGridDay"
    };
    var VIEW_REVERSE = {
        dayGridMonth: "month",
        timeGridWeek: "week",
        timeGridDay:  "day"
    };

    /* -------------------------------------------------------------- */
    function init(root) {
        var key   = root.getAttribute("data-mascal");
        var data  = global.__MASCAL_DATA && global.__MASCAL_DATA[key];
        if (!data) { return; }
        if (root.__mascalInit) { return; }
        root.__mascalInit = true;

        var opts       = data.options || {};
        var showLegend = opts.showLegend !== false;
        var readOnly   = opts.readonly === true;
        var startView  = VIEW_MAP[opts.defaultView] || "dayGridMonth";
        var height     = parseInt(opts.height, 10) || 600;

        var calEl = root.querySelector(".mascal-calendar");
        if (!calEl || !global.FullCalendar) {
            /* Library not yet loaded; retry shortly. */
            setTimeout(function () { init(root); }, 100);
            return;
        }

        var FullCalendar = global.FullCalendar;

        /* Mutable visibility maps (seeded from data).
           Key scheme:
             flat filter node:  "<p|s>:" + key
             tree group node:   "<p|s>g:" + groupKey
             tree child node:   "<p|s>c:" + groupKey + "\u0001" + key   */
        var pVis = {};
        var sVis = {};
        seedVis(pVis, data.primary, "p");
        seedVis(sVis, data.secondary, "s");

        /* The visibility keys that apply to a given event. */
        function eventKeys(e) {
            var o = data.options || {};
            var pk = null, sk = null;
            if (o.hasPrimary) {
                pk = o.hasPrimaryGroup
                    ? ["pg:" + e.primaryGroupKey, "pc:" + e.primaryGroupKey + "\u0001" + e.primaryKey]
                    : ["p:" + e.primaryKey];
            }
            if (o.hasSecondary) {
                sk = o.hasSecondaryGroup
                    ? ["sg:" + e.secondaryGroupKey, "sc:" + e.secondaryGroupKey + "\u0001" + e.secondaryKey]
                    : ["s:" + e.secondaryKey];
            }
            return { p: pk, s: sk };
        }

        /* Filtered event source: returns only currently-visible events. */
        function visibleEvents() {
            return (data.events || []).filter(function (e) {
                var k = eventKeys(e);
                var i;
                if (k.p) { for (i = 0; i < k.p.length; i++) { if (pVis[k.p[i]] === false) return false; } }
                if (k.s) { for (i = 0; i < k.s.length; i++) { if (sVis[k.s[i]] === false) return false; } }
                return true;
            });
        }

        var dayDialog = null;

        function formatTime(value) {
            var parts = /^(\d{1,2}):(\d{2})/.exec(value || "");
            if (!parts) { return ""; }
            var hour = parseInt(parts[1], 10);
            return (hour % 12 || 12) + ":" + parts[2] + (hour < 12 ? "AM" : "PM");
        }

        function eventContent(event, showWorkHours) {
            var props = event.extendedProps || {};
            var desc = props.desc == null ? "" : String(props.desc).trim();
            var wrapper = document.createElement("div");
            wrapper.className = "mascal-event-content";

            var titleEl = document.createElement("div");
            titleEl.className = "mascal-event-title";
            titleEl.textContent = (event.title || "") + (desc ? "  " + desc : "");
            wrapper.appendChild(titleEl);

            var startTime = props.displayStartTime == null ? (event.startStr || "").slice(11, 16) : props.displayStartTime;
            var endTime = props.displayEndTime == null ? (event.endStr || "").slice(11, 16) : props.displayEndTime;
            startTime = formatTime(startTime);
            endTime = formatTime(endTime);
            if (startTime || endTime) {
                var timeEl = document.createElement("div");
                timeEl.className = "mascal-event-time";
                timeEl.textContent = startTime && endTime ? startTime + " - " + endTime : startTime || endTime;
                if (showWorkHours && props.workHours != null && props.workHours !== "") {
                    timeEl.textContent += " (" + props.workHours + " hours)";
                }
                wrapper.appendChild(timeEl);
            }
            return wrapper;
        }

        function openDayDialog(info) {
            var existing = document.querySelector(".mascal-day-dialog");
            if (existing) { existing.close(); }

            var cell = info.el.closest("[data-date]");
            var dateKey = cell ? cell.getAttribute("data-date").slice(0, 10) : info.event.startStr.slice(0, 10);
            var dayStart = new Date(dateKey + "T00:00:00");
            var dayEnd = new Date(dayStart.getTime());
            dayEnd.setDate(dayEnd.getDate() + 1);
            var events = calendar.getEvents().filter(function (event) {
                return event.start && event.start < dayEnd &&
                    (event.end && event.end > event.start ? event.end > dayStart : event.start >= dayStart);
            }).sort(function (left, right) {
                return left.start - right.start || (left.title || "").localeCompare(right.title || "");
            });

            var dialog = document.createElement("dialog");
            dialog.className = "mascal-day-dialog";
            dialog.setAttribute("aria-modal", "true");
            dialog.setAttribute("aria-labelledby", key + "_day_title");
            var header = document.createElement("div");
            header.className = "mascal-day-header";
            var heading = document.createElement("h2");
            heading.id = key + "_day_title";
            heading.textContent = dayStart.toLocaleDateString(undefined, {
                weekday: "long", year: "numeric", month: "long", day: "numeric"
            });
            var close = document.createElement("button");
            close.type = "button";
            close.className = "mascal-day-close";
            close.textContent = "\u00d7";
            close.setAttribute("aria-label", "Close day events");
            close.title = "Close";
            close.addEventListener("click", function () { dialog.close(); });
            header.appendChild(heading);
            header.appendChild(close);
            dialog.appendChild(header);

            var list = document.createElement("ol");
            list.className = "mascal-day-events";
            events.forEach(function (event) {
                var item = document.createElement("li");
                item.style.borderLeftColor = event.backgroundColor || "#888";
                item.appendChild(eventContent(event, true));
                list.appendChild(item);
            });
            dialog.appendChild(list);
            dialog.addEventListener("close", function () {
                dialog.remove();
                if (dayDialog === dialog) { dayDialog = null; }
            });
            document.body.appendChild(dialog);
            dayDialog = dialog;
            dialog.showModal();
            close.focus();
        }

        /* ---------------- FullCalendar instance -------------------- */
        var calendar = new FullCalendar.Calendar(calEl, {
            initialView:  startView,
            height:       height,
            headerToolbar: {
                left:   "prev,next today",
                center: "title",
                right:  "dayGridMonth,timeGridDay"
            },
            slotMinTime: "00:00:00",
            slotMaxTime: "24:00:00",
            nowIndicator: true,
            dayMaxEvents: true,
            editable:      !readOnly,
            eventStartEditable:  !readOnly,
            eventDurationEditable: !readOnly,
            eventResizableFromStart: !readOnly,
            events: function (info, success) { success(visibleEvents()); },

            /* Colour the event block by primary filter value (per-event color already set,
               but we also add a class for styling hooks). */
            eventClassNames: function (arg) {
                return ["mascal-event"];
            },
            eventDidMount: function (arg) {
                var e = arg.el;
                if (!e) { return; }
                e.style.borderLeft = "3px solid " + (arg.event.backgroundColor || "#888");

                var p = arg.event.extendedProps || {};

                /* Re-apply the focus highlight to the event that matches the
                   DataBean's current MBO (survives the post-select reload). */
                if (p.focused) {
                    e.classList.add("mascal-event-focused");
                }
            },

            /* ---- Drag / resize callbacks (only fired when editable) ---- */
            eventDrop: function (info) { handleEdit(info, "move"); },
            eventResize: function (info) { handleEdit(info, "resize"); },

            eventClick: function (info) {
                info.jsEvent.preventDefault();
                openDayDialog(info);
                MASCAL.fire("eventclick", { id: info.event.id, rootId: key, jsEvent: info.jsEvent });
            },
            eventContent: function (arg) {
                return { domNodes: [eventContent(arg.event)] };
            }
        });

        calendar.render();

        /* Persist a drag/resize back to Maximo via the calendar servlet.
           Failures roll the visual change back. */
        function handleEdit(info, type) {
            var ev   = info.event;
            var data_ = {
                id:    ev.id,
                start: ev.start ? ev.start.toISOString() : null,
                end:   ev.end   ? ev.end.toISOString()   : null
            };
            var body = "action=" + type +
                       "&ctrlId=" + encodeURIComponent(key) +
                       "&eventId=" + encodeURIComponent(data_.id) +
                       "&start="   + encodeURIComponent(data_.start || "") +
                       "&end="     + encodeURIComponent(data_.end   || "");
            var xhr = new XMLHttpRequest();
            xhr.open("POST", servletUrl(), true);
            xhr.setRequestHeader("Content-Type",
                                  "application/x-www-form-urlencoded; charset=UTF-8");
            xhr.onreadystatechange = function () {
                if (xhr.readyState !== 4) return;
                if (xhr.status !== 200 || xhr.responseText.indexOf('"ok"') === -1) {
                    info.revert();   /* undo the move on failure */
                    MASCAL.fire("editerror", { id: data_.id, status: xhr.status, body: xhr.responseText });
                } else {
                    MASCAL.fire("editsaved", { id: data_.id });
                }
            };
            xhr.send(body);
        }
        /* ---------------- Legend rendering ------------------------- */
        if (showLegend) { buildLegend(root, data, pVis, sVis, refresh); }

        function refresh() {
            if (dayDialog) { dayDialog.close(); }
            calendar.refetchEvents();
        }

        /* Expose a tiny handle so the host page can poke the control. */
        MASCAL.instances = MASCAL.instances || {};
        MASCAL.instances[key] = {
            getCalendar: function () { return calendar; },
            refresh:     refresh,
            setData:     function (d) {
                data = d;
                pVis = {}; sVis = {};
                seedVis(pVis, data.primary, "p");
                seedVis(sVis, data.secondary, "s");
                refresh();
                if (showLegend) { buildLegend(root, data, pVis, sVis, refresh); }
            }
        };
    }

    /* Seed a visibility map from a legend node list (all visible). */
    function seedVis(map, nodes, prefix) {
        (nodes || []).forEach(function (n) {
            if (n.children && n.children.length) {
                map[prefix + "g:" + n.key] = true;
                n.children.forEach(function (c) {
                    map[prefix + "c:" + n.key + "\u0001" + c.key] = true;
                });
            } else {
                map[prefix + ":" + n.key] = true;
            }
        });
    }

    /* Build the two-tab legend (Primary filter + optional Secondary filter).
       Each tab is a flat list, or a two-level tree when a group-by attribute
       is configured for that filter. */
    function buildLegend(root, data, pVis, sVis, onChange) {
        var legend = root.querySelector(".mascal-legend");
        if (!legend) return;

        var tabs      = legend.querySelectorAll(".mascal-tab");
        var panels    = legend.querySelectorAll(".mascal-tabpanel");
        var primaryUl = legend.querySelector('[data-panel="people"]');
        var secUl     = legend.querySelector('[data-panel="secondary"]');
        var secTab    = legend.querySelector('.mascal-tab[data-tab="secondary"]');

        /* Show secondary tab only if there is a secondary filter attribute. */
        if (data.options.hasSecondary && secTab) {
            secTab.style.display = "";
            secTab.textContent   = data.secondaryLabel || "Secondary";
        }

        /* Populate Primary filter list (flat or tree). */
        renderTree(primaryUl, data.primary || [], "p", pVis, onChange);

        /* Populate Secondary list (flat or tree). */
        renderTree(secUl, data.secondary || [], "s", sVis, onChange);

        /* Tab switching. */
        tabs.forEach(function (tab) {
            tab.onclick = function () {
                var which = tab.getAttribute("data-tab");
                tabs.forEach(function (t)   { t.classList.toggle("active",   t === tab); });
                panels.forEach(function (p) { p.classList.toggle("active",   p.getAttribute("data-panel") === which); });
            };
        });
    }

    /* Render a legend list. Nodes with a non-empty `children` array are
       group-by (root) nodes; their children are the filter values found
       under that group. Both levels are independently toggleable:
       - toggling a group toggles every filter under it;
       - toggling a filter only affects that filter, and keeps the group
         checkbox in sync (checked / indeterminate / unchecked). */
    function renderTree(ul, nodes, prefix, visMap, onChange) {
        if (!ul) return;
        ul.innerHTML = "";
        (nodes || []).forEach(function (node) {
            var isGroup = !!(node.children && node.children.length);
            var key = isGroup ? prefix + "g:" + node.key : prefix + ":" + node.key;

            var li = document.createElement("li");
            li.className = "mascal-legend-row" + (isGroup ? " mascal-legend-group" : "");

            var cb = document.createElement("input");
            cb.type    = "checkbox";
            cb.checked = visMap[key] !== false;

            if (isGroup) {
                var childKeys = node.children.map(function (c) {
                    return prefix + "c:" + node.key + "\u0001" + c.key;
                });
                var childCbs = [];   /* child checkboxes, for group sync */

                li.appendChild(cb);
                li.appendChild(makeSwatch(node.color || "#999"));
                li.appendChild(makeLabel(node.label, "mascal-legend-label mascal-legend-group-label"));
                ul.appendChild(li);

                node.children.forEach(function (child) {
                    var ckey = prefix + "c:" + node.key + "\u0001" + child.key;
                    var cli  = document.createElement("li");
                    cli.className = "mascal-legend-row mascal-legend-child";

                    var ccb = document.createElement("input");
                    ccb.type    = "checkbox";
                    ccb.checked = visMap[ckey] !== false;
                    childCbs.push(ccb);
                    ccb.addEventListener("change", function () {
                        visMap[ckey] = ccb.checked;
                        /* Keep the group checkbox in sync: checked when all
                           children are on, indeterminate when mixed, unchecked
                           when none are. The group itself stays "visible" as
                           long as at least one child is, so the visible
                           children still show. */
                        var all = true, none = true;
                        childKeys.forEach(function (k2) {
                            if (visMap[k2] === false) { all = false; } else { none = false; }
                        });
                        visMap[key] = !none;
                        cb.checked = all;
                        cb.indeterminate = !all && !none;
                        onChange();
                    });
                    cli.appendChild(ccb);
                    cli.appendChild(makeSwatch(child.color || "#888"));
                    cli.appendChild(makeLabel(child.label, "mascal-legend-label"));
                    ul.appendChild(cli);
                });

                /* Toggling a group toggles every filter under it. */
                cb.addEventListener("change", function () {
                    visMap[key] = cb.checked;
                    childKeys.forEach(function (ck) { visMap[ck] = cb.checked; });
                    childCbs.forEach(function (c2) {
                        c2.checked = cb.checked;
                        c2.indeterminate = false;
                    });
                    onChange();
                });
            } else {
                cb.addEventListener("change", function () {
                    visMap[key] = cb.checked;
                    onChange();
                });
                li.appendChild(cb);
                li.appendChild(makeSwatch(node.color || "#888"));
                li.appendChild(makeLabel(node.label, "mascal-legend-label"));
                ul.appendChild(li);
            }
        });
    }

    function makeSwatch(color) {
        var sw = document.createElement("span");
        sw.className = "mascal-swatch";
        sw.style.background = color;
        return sw;
    }

    function makeLabel(text, cls) {
        var lbl = document.createElement("span");
        lbl.className = cls;
        lbl.textContent = text;
        return lbl;
    }

    /* Tiny event bus for host-page hooks. */
    MASCAL._listeners = MASCAL._listeners || {};
    MASCAL.on    = function (name, fn) { (MASCAL._listeners[name] = MASCAL._listeners[name] || []).push(fn); };
    MASCAL.fire  = function (name, payload) {
        (MASCAL._listeners[name] || []).forEach(function (fn) { try { fn(payload); } catch (e) {} });
    };

    /* Scan & init every control root on the page once DOM is ready. */
    function scan() {
        var roots = document.querySelectorAll(".mascal-root");
        for (var i = 0; i < roots.length; i++) { init(roots[i]); }
    }
    if (document.readyState === "complete" || document.readyState === "interactive") {
        setTimeout(scan, 0);
    } else {
        document.addEventListener("DOMContentLoaded", scan);
    }
})(window);
