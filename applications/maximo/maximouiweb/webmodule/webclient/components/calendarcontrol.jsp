<%@ page import="java.text.SimpleDateFormat"%>
<%@ page import="java.util.Calendar"%>
<%@ page import="java.util.ArrayList"%>
<%@ page import="java.util.Date"%>
<%@ page import="java.util.HashMap"%>
<%@ page import="java.util.HashSet"%>
<%@ page import="java.util.LinkedHashMap"%>
<%@ page import="java.util.LinkedHashSet"%>
<%@ page import="java.util.List"%>
<%@ page import="java.util.Locale"%>
<%@ page import="java.util.Map"%>
<%@ page import="java.util.Set"%>
<%@ page import="psdi.mbo.MboRemote"%>
<%@ page import="psdi.mbo.MboSetRemote"%>
<%@ page import="psdi.util.MXException"%>
<%@ page import="psdi.webclient.system.beans.DataBean"%>
<%@ page import="com.ibm.json.java.JSONArray"%>
<%@ page import="com.ibm.json.java.JSONObject"%>
<%
/*
    calendarcontrol.jsp  -  reusable MAS calendar control renderer.
    ----------------------------------------------------------------
    Bound component (parent = BoundComponentInstance) - re-renders
    automatically whenever the parent DataBean's MBO changes, which
    is what makes it survive the Next/Previous toolbar buttons.
*/
%>
<%@ include file="../common/componentheader.jsp"%>
<%
    if (designmode)
    {
        %><tr style="min-height:50px;"><td><div style="min-height:50px;background-color:#dce8f5;width:100%;padding:10px;box-sizing:border-box;font-family:sans-serif;color:#2e6da4;border:1px dashed #2e6da4;">Calendar Control (design view)</div></td></tr><%
    }
    else
    {
%>
<%
    // ----------------------------------------------------------------
    // 1.  Read all properties that the developer supplied via the
    // ----------------------------------------------------------------
    // -- Method 1: combined start/end datetime attributes --
    String startAttr     = component.getProperty("startattribute");
    String endAttr       = component.getProperty("endattribute");
    // -- Method 2: work date + separate start/end time attributes --
    String workdateAttr  = component.getProperty("workdateattribute");
    String starttimeAttr = component.getProperty("starttimeattribute");
    String endtimeAttr   = component.getProperty("endtimeattribute");
    // -- Method 3: date range + separate start/end time attributes --
    // (shares starttimeAttr / endtimeAttr with method 2)
    String startdaterangeAttr = component.getProperty("startdaterangeattribute");
    String enddaterangeAttr   = component.getProperty("enddaterangeattribute");
    // -- Title --
    String titleAttr     = component.getProperty("titleattribute");
    // -- Primary filter (replaces personattribute) --
    String primaryFilterValueAttr   = component.getProperty("primaryfiltervalue");
    String primaryFilterDisplayAttr = component.getProperty("primaryfilterdisplay");
    String primaryFilterLabel       = component.getProperty("primaryfilterlabel");
    // -- Secondary filter --
    String secondaryFilterValueAttr   = component.getProperty("secondaryfiltervalue");
    String secondaryFilterDisplayAttr = component.getProperty("secondaryfilterdisplay");
    String secLabel      = component.getProperty("secondaryfilterlabel");
    // -- Primary filter group-by (two-level tree legend) --
    String primaryGroupByValueAttr   = component.getProperty("primarygroupbyvalue");
    String primaryGroupByDisplayAttr = component.getProperty("primarygroupbydisplay");
    // -- Secondary filter group-by (two-level tree legend) --
    String secondaryGroupByValueAttr   = component.getProperty("secondarygroupbyvalue");
    String secondaryGroupByDisplayAttr = component.getProperty("secondarygroupbydisplay");
    // -- Duplicate removal (semi-colon / comma separated column names) --
    String dupColumns = component.getProperty("duplicatecolumns");
    // -- Secondary label rendered under the title on each event --
    String descAttr = component.getProperty("descattribute");
    // -- Appearance / behaviour --
    String strHeight     = component.getProperty("height");
    String defaultView   = component.getProperty("defaultview");
    String strReadonly   = component.getProperty("readonly");
    String strShowLegend = component.getProperty("showlegend");
    String assetPath     = component.getProperty("assetpath");
    String cssClass      = component.getProperty("cssclass");
    String datasrc       = component.getProperty("datasrc");

    if (startAttr     == null) startAttr     = "";
    if (endAttr       == null) endAttr       = "";
    if (workdateAttr  == null) workdateAttr  = "";
    if (starttimeAttr == null) starttimeAttr = "";
    if (endtimeAttr   == null) endtimeAttr   = "";
    if (startdaterangeAttr == null) startdaterangeAttr = "";
    if (enddaterangeAttr   == null) enddaterangeAttr   = "";
    if (titleAttr     == null) titleAttr     = "";
    if (primaryFilterValueAttr   == null) primaryFilterValueAttr   = "";
    if (primaryFilterDisplayAttr == null) primaryFilterDisplayAttr = "";
    if (primaryFilterLabel == null || primaryFilterLabel.trim().length() == 0) primaryFilterLabel = "People";
    if (secondaryFilterValueAttr   == null) secondaryFilterValueAttr   = "";
    if (secondaryFilterDisplayAttr == null) secondaryFilterDisplayAttr = "";
    if (secLabel    == null) secLabel    = "Secondary Filter";
    if (primaryGroupByValueAttr   == null) primaryGroupByValueAttr   = "";
    if (primaryGroupByDisplayAttr == null) primaryGroupByDisplayAttr = "";
    if (secondaryGroupByValueAttr   == null) secondaryGroupByValueAttr   = "";
    if (secondaryGroupByDisplayAttr == null) secondaryGroupByDisplayAttr = "";
    if (dupColumns == null) dupColumns = "";
    if (descAttr   == null) descAttr   = "";
    if (defaultView == null || defaultView.trim().length()==0) defaultView = "month";
    if (strHeight   == null || strHeight.trim().length()==0) strHeight = "600";
    boolean calReadOnly   = "true".equalsIgnoreCase(strReadonly);
    boolean showLegend = !"false".equalsIgnoreCase(strShowLegend);

    // Duplicate-removal columns (case insensitive; Maximo MBO attribute
    // lookup is case insensitive, so the names may be entered in any case).
    List<String> dupColList = new ArrayList<String>();
    for (String part : dupColumns.split("[;,]")) {
        if (part.trim().length() > 0) dupColList.add(part.trim());
    }

    // A group-by only takes effect when its associated filter is configured.
    boolean hasPrimaryGroup   = primaryFilterValueAttr.length() > 0 && primaryGroupByValueAttr.length() > 0;
    boolean hasSecondaryGroup = secondaryFilterValueAttr.length() > 0 && secondaryGroupByValueAttr.length() > 0;

    // FullCalendar static asset path. Default to webclient/lib (see README).
    String ctx = request.getContextPath();
    String libPath;
    if (assetPath != null && assetPath.trim().length() > 0) {
        libPath = assetPath;
    } else {
        libPath = ctx + "/webclient/lib";
    }
    if (libPath.endsWith("/")) libPath = libPath.substring(0, libPath.length() - 1);

    // ----------------------------------------------------------------
    // 2.  Resolve the DataBean / MboSet that holds the events.
    //     - If `datasrc` is supplied, use that sub-bean.
    //     - Otherwise fall back to the page's primary bean.
    // ----------------------------------------------------------------
    // component.getDataBean() already resolves the configured datasrc binding.
    // Fall back to the page's primary bean if the component is unbound.
    DataBean evBean = component.getDataBean();
    if (evBean == null) evBean = control.getPage().getDataBean();

    // Unique id for this control instance (multiple per page supported)
    String ctrlId = component.getId();
    if (ctrlId == null || ctrlId.length() == 0) {
        ctrlId = "mascal_" + System.identityHashCode(component);
    }

    // ----------------------------------------------------------------
    // 3.  Walk the MboSet, build event + legend data.
    // ----------------------------------------------------------------
    final String[] PALETTE = {
        "#2e6da4", "#5cb85c", "#d9534f", "#f0ad4e", "#5bc0de",
        "#9b59b6", "#1abc9c", "#e67e22", "#34495e", "#c0392b",
        "#16a085", "#8e44ad"
    };
    int colorIdx = 0;
    Map<String,String> primaryColor  = new LinkedHashMap<String,String>();
    Map<String,String> primaryLabels = new LinkedHashMap<String,String>();
    Map<String,String> secondaryLbl = new LinkedHashMap<String,String>();
    Set<String> secondaryKeys       = new LinkedHashSet<String>();
    Set<String> seenSecondaryLbl    = new HashSet<String>();

    // ---- Group-by (two-level tree legend) structures ----
    // groupKey -> display label
    Map<String,String> primaryGroupLabels   = new LinkedHashMap<String,String>();
    Map<String,String> secondaryGroupLabels = new LinkedHashMap<String,String>();
    // groupKey -> (filterKey -> filter display label), insertion ordered
    Map<String,Map<String,String>> primaryTree   = new LinkedHashMap<String,Map<String,String>>();
    Map<String,Map<String,String>> secondaryTree = new LinkedHashMap<String,Map<String,String>>();
    // ---- Duplicate removal: seen combinations of the dup columns ----
    Set<String> seenDupKeys = new HashSet<String>();

    JSONArray events = new JSONArray();
    SimpleDateFormat iso = new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.US);
    SimpleDateFormat timeFormat = new SimpleDateFormat("HH:mm", Locale.US);

    if (evBean != null) {
        // Capture the DataBean's current MBO BEFORE the iteration below: the
        // loop's getMbo(i) calls move the current MBO as they walk. The event
        // belonging to this MBO is flagged "focused" so the client can
        // highlight it (it is the record a single click will select).
        String currentMboId = "";
        try {
            MboRemote curMbo = evBean.getMbo();
            if (curMbo != null) currentMboId = String.valueOf(curMbo.getUniqueIDValue());
        } catch (Exception ex) {}

        evBean.reset();
        MboRemote mbo = null;
        int i = 0;
        while ((mbo = evBean.getMbo(i)) != null) {

            // ----------------------------------------------------------------
            // Determine the event date method and build a list of {start, end}
            // pairs. Method 3 may produce multiple pairs from a single MBO.
            // Each entry: [0]=startStr, [1]=endStr, [2]=uniqueSuffix
            // ----------------------------------------------------------------
            List<String[]> dateRanges = new ArrayList<String[]>();

            if (startdaterangeAttr.length() > 0) {
                // ---- Method 3: STARTDATERANGE + ENDDATERANGE + STARTTIME + ENDTIME ----
                try {
                    Date rangeStart = mbo.getDate(startdaterangeAttr);
                    Date rangeEnd   = (enddaterangeAttr.length() > 0) ? mbo.getDate(enddaterangeAttr) : null;
                    if (rangeEnd == null) rangeEnd = rangeStart;
                    if (rangeStart != null) {
                        Date startTime = null, endTime = null;
                        if (starttimeAttr.length() > 0) try { startTime = mbo.getDate(starttimeAttr); } catch (Exception ex) {}
                        if (endtimeAttr.length()   > 0) try { endTime   = mbo.getDate(endtimeAttr);   } catch (Exception ex) {}

                        Calendar curDay = Calendar.getInstance();
                        curDay.setTime(rangeStart);
                        curDay.set(Calendar.HOUR_OF_DAY, 0); curDay.set(Calendar.MINUTE, 0);
                        curDay.set(Calendar.SECOND, 0);      curDay.set(Calendar.MILLISECOND, 0);

                        Calendar lastDay = Calendar.getInstance();
                        lastDay.setTime(rangeEnd);
                        lastDay.set(Calendar.HOUR_OF_DAY, 0); lastDay.set(Calendar.MINUTE, 0);
                        lastDay.set(Calendar.SECOND, 0);      lastDay.set(Calendar.MILLISECOND, 0);

                        int dayIdx = 0;
                        while (!curDay.after(lastDay)) {
                            String dStart, dEnd = "";
                            if (startTime != null) {
                                Calendar stCal = Calendar.getInstance();
                                stCal.setTime(startTime);
                                Calendar comb = (Calendar) curDay.clone();
                                comb.set(Calendar.HOUR_OF_DAY, stCal.get(Calendar.HOUR_OF_DAY));
                                comb.set(Calendar.MINUTE, stCal.get(Calendar.MINUTE));
                                comb.set(Calendar.SECOND, 0); comb.set(Calendar.MILLISECOND, 0);
                                dStart = iso.format(comb.getTime());
                            } else {
                                dStart = iso.format(curDay.getTime());
                            }
                            if (endTime != null) {
                                Calendar etCal = Calendar.getInstance();
                                etCal.setTime(endTime);
                                Calendar comb = (Calendar) curDay.clone();
                                comb.set(Calendar.HOUR_OF_DAY, etCal.get(Calendar.HOUR_OF_DAY));
                                comb.set(Calendar.MINUTE, etCal.get(Calendar.MINUTE));
                                comb.set(Calendar.SECOND, 0); comb.set(Calendar.MILLISECOND, 0);
                                dEnd = iso.format(comb.getTime());
                            }
                            dateRanges.add(new String[]{ dStart, dEnd, String.valueOf(dayIdx) });
                            curDay.add(Calendar.DATE, 1);
                            dayIdx++;
                        }
                    }
                } catch (Exception ex) { /* skip */ }

            } else if (workdateAttr.length() > 0) {
                // ---- Method 2: WORKDATE + STARTTIME + ENDTIME ----
                try {
                    Date workDate = mbo.getDate(workdateAttr);
                    if (workDate != null) {
                        Date startTime = null, endTime = null;
                        if (starttimeAttr.length() > 0) try { startTime = mbo.getDate(starttimeAttr); } catch (Exception ex) {}
                        if (endtimeAttr.length()   > 0) try { endTime   = mbo.getDate(endtimeAttr);   } catch (Exception ex) {}

                        Calendar wdCal = Calendar.getInstance();
                        wdCal.setTime(workDate);
                        wdCal.set(Calendar.HOUR_OF_DAY, 0); wdCal.set(Calendar.MINUTE, 0);
                        wdCal.set(Calendar.SECOND, 0);      wdCal.set(Calendar.MILLISECOND, 0);

                        String dStart, dEnd = "";
                        if (startTime != null) {
                            Calendar stCal = Calendar.getInstance();
                            stCal.setTime(startTime);
                            Calendar comb = (Calendar) wdCal.clone();
                            comb.set(Calendar.HOUR_OF_DAY, stCal.get(Calendar.HOUR_OF_DAY));
                            comb.set(Calendar.MINUTE, stCal.get(Calendar.MINUTE));
                            comb.set(Calendar.SECOND, 0); comb.set(Calendar.MILLISECOND, 0);
                            dStart = iso.format(comb.getTime());
                        } else {
                            dStart = iso.format(workDate);
                        }
                        if (endTime != null) {
                            Calendar etCal = Calendar.getInstance();
                            etCal.setTime(endTime);
                            Calendar comb = (Calendar) wdCal.clone();
                            comb.set(Calendar.HOUR_OF_DAY, etCal.get(Calendar.HOUR_OF_DAY));
                            comb.set(Calendar.MINUTE, etCal.get(Calendar.MINUTE));
                            comb.set(Calendar.SECOND, 0); comb.set(Calendar.MILLISECOND, 0);
                            dEnd = iso.format(comb.getTime());
                        }
                        dateRanges.add(new String[]{ dStart, dEnd, "" });
                    }
                } catch (Exception ex) { /* skip */ }

            } else {
                // ---- Method 1: STARTDATETIME + ENDDATETIME ----
                String dStart = "", dEnd = "";
                try {
                    if (startAttr.length() > 0) {
                        Date d = mbo.getDate(startAttr);
                        if (d != null) dStart = iso.format(d);
                    }
                } catch (Exception ex) {}
                try {
                    if (endAttr.length() > 0) {
                        Date d = mbo.getDate(endAttr);
                        if (d != null) dEnd = iso.format(d);
                    }
                } catch (Exception ex) {}
                if (dStart.length() > 0) {
                    dateRanges.add(new String[]{ dStart, dEnd, "" });
                }
            }

            if (dateRanges.isEmpty()) { i++; continue; } // nothing to plot

            // ---- Duplicate removal: keep only the first MBO for each unique
            //      combination of the configured column values. ----
            if (!dupColList.isEmpty()) {
                StringBuilder dupKey = new StringBuilder();
                for (int d = 0; d < dupColList.size(); d++) {
                    String dv = "";
                    try {
                        String v = mbo.getString(dupColList.get(d));
                        if (v != null) dv = v;
                    } catch (Exception ex) {}
                    dupKey.append(dv).append('\u0001');
                }
                if (!seenDupKeys.add(dupKey.toString())) { i++; continue; }
            }

            // ---- Title ----
            String evTitle = "";
            try {
                if (titleAttr.length() > 0) evTitle = mbo.getString(titleAttr);
            } catch (Exception ex) {}

            // ---- Primary filter grouping / colour ----
            String primaryKey = "";
            try {
                if (primaryFilterValueAttr.length() > 0) primaryKey = mbo.getString(primaryFilterValueAttr);
            } catch (Exception ex) {}
            if (primaryKey == null) primaryKey = "";

            String primaryDisplay = primaryKey;
            try {
                if (primaryFilterDisplayAttr.length() > 0) {
                    String d = mbo.getString(primaryFilterDisplayAttr);
                    if (d != null && d.length() > 0) primaryDisplay = d;
                }
            } catch (Exception ex) {}

            String displayLabel = primaryKey.length() == 0 ? "(unassigned)" : primaryDisplay;
            if (!primaryColor.containsKey(primaryKey)) {
                String c = PALETTE[colorIdx % PALETTE.length];
                colorIdx++;
                primaryColor.put(primaryKey, c);
                primaryLabels.put(primaryKey, displayLabel);
            }

            // ---- Secondary filter value ----
            String secKey = "";
            try {
                if (secondaryFilterValueAttr.length() > 0) secKey = mbo.getString(secondaryFilterValueAttr);
            } catch (Exception ex) {}
            if (secKey == null) secKey = "";

            String secDisplay = secKey;
            try {
                if (secondaryFilterDisplayAttr.length() > 0) {
                    String d = mbo.getString(secondaryFilterDisplayAttr);
                    if (d != null && d.length() > 0) secDisplay = d;
                }
            } catch (Exception ex) {}

            if (secondaryFilterValueAttr.length() > 0 && seenSecondaryLbl.add(secKey)) {
                secondaryKeys.add(secKey);
                secondaryLbl.put(secKey, secKey.length() == 0 ? "(blank)" : secDisplay);
            }

            // ---- Description (secondary label rendered under the title) ----
            String evDesc = "";
            try {
                if (descAttr.length() > 0) {
                    String v = mbo.getString(descAttr);
                    if (v != null) evDesc = v;
                }
            } catch (Exception ex) {}

            // ---- Primary group-by value (tree legend) ----
            String pGroupKey = "";
            if (hasPrimaryGroup) {
                try {
                    String v = mbo.getString(primaryGroupByValueAttr);
                    if (v != null) pGroupKey = v;
                } catch (Exception ex) {}
                String pGroupDisplay = pGroupKey;
                if (primaryGroupByDisplayAttr.length() > 0) {
                    try {
                        String v = mbo.getString(primaryGroupByDisplayAttr);
                        if (v != null && v.length() > 0) pGroupDisplay = v;
                    } catch (Exception ex) {}
                }
                if (!primaryGroupLabels.containsKey(pGroupKey)) {
                    primaryGroupLabels.put(pGroupKey, pGroupKey.length() == 0 ? "(unassigned)" : pGroupDisplay);
                }
                Map<String,String> pKids = primaryTree.get(pGroupKey);
                if (pKids == null) {
                    pKids = new LinkedHashMap<String,String>();
                    primaryTree.put(pGroupKey, pKids);
                }
                if (!pKids.containsKey(primaryKey)) {
                    pKids.put(primaryKey, primaryKey.length() == 0 ? "(unassigned)" : primaryDisplay);
                }
            }

            // ---- Secondary group-by value (tree legend) ----
            String sGroupKey = "";
            if (hasSecondaryGroup) {
                try {
                    String v = mbo.getString(secondaryGroupByValueAttr);
                    if (v != null) sGroupKey = v;
                } catch (Exception ex) {}
                String sGroupDisplay = sGroupKey;
                if (secondaryGroupByDisplayAttr.length() > 0) {
                    try {
                        String v = mbo.getString(secondaryGroupByDisplayAttr);
                        if (v != null && v.length() > 0) sGroupDisplay = v;
                    } catch (Exception ex) {}
                }
                if (!secondaryGroupLabels.containsKey(sGroupKey)) {
                    secondaryGroupLabels.put(sGroupKey, sGroupKey.length() == 0 ? "(unassigned)" : sGroupDisplay);
                }
                Map<String,String> sKids = secondaryTree.get(sGroupKey);
                if (sKids == null) {
                    sKids = new LinkedHashMap<String,String>();
                    secondaryTree.put(sGroupKey, sKids);
                }
                if (!sKids.containsKey(secKey)) {
                    sKids.put(secKey, secKey.length() == 0 ? "(blank)" : secDisplay);
                }
            }

            String evStartTime = "", evEndTime = "";
            try {
                Date value = mbo.getDate(starttimeAttr.length() > 0 ? starttimeAttr : "STARTTIME");
                if (value != null) evStartTime = timeFormat.format(value);
            } catch (Exception ex) {}
            try {
                Date value = mbo.getDate(endtimeAttr.length() > 0 ? endtimeAttr : "ENDTIME");
                if (value != null) evEndTime = timeFormat.format(value);
            } catch (Exception ex) {}
            Double evWorkHours = null;
            String evWorkHoursError = null;
            try {
                evWorkHours = Double.valueOf(mbo.getDouble("WORKHOURS"));
            } catch (Exception ex) {
                evWorkHoursError = ex.getClass().getName();
                application.log("Calendar control " + ctrlId + ": unable to read WORKHOURS for row " + i, ex);
            }

            // ---- Build one event object per date range entry ----
            String mboId = String.valueOf(mbo.getString("PRIMARYID"));
            for (String[] dr : dateRanges) {
                String dStart  = dr[0];
                String dEnd    = dr[1].length() > 0 ? dr[1] : dStart; // treat as point if no end
                String suffix  = dr[2].length() > 0 ? "_" + dr[2] : "";
                /* Same start and end -> render as an all-day event on that date. */
                boolean allDay = dStart.equals(dEnd);
                JSONObject ev = new JSONObject();
                ev.put("id",           mboId + suffix);
                if (allDay) {
                    ev.put("start",  dStart.substring(0, 10));
                    ev.put("allDay", true);
                } else {
                    ev.put("start", dStart);
                    ev.put("end",   dEnd);
                }
                ev.put("title",        evTitle == null ? "" : evTitle);
                ev.put("desc",         evDesc);
                ev.put("displayStartTime", evStartTime.length() > 0 ? evStartTime : dStart.substring(11, 16));
                ev.put("displayEndTime", evEndTime.length() > 0 ? evEndTime : (dr[1].length() > 0 ? dr[1].substring(11, 16) : ""));
                ev.put("workHours",    evWorkHours);
                if (evWorkHoursError != null) ev.put("workHoursReadError", evWorkHoursError);
                ev.put("mboId",        mboId);
                ev.put("rowIndex",     i);
                ev.put("focused",      mboId.equals(currentMboId));
                ev.put("primaryKey",   primaryKey);
                ev.put("primaryGroupKey", pGroupKey);
                ev.put("color",        primaryColor.get(primaryKey));
                ev.put("secondaryKey", secKey);
                ev.put("secondaryGroupKey", sGroupKey);
                events.add(ev);
            }

            i++;
        }
    }

    // ---- Build legend structures ----
    // Without a group-by: a flat list of filter values (as before).
    // With a group-by: a two-level tree - group-by values at the root,
    // the filter values found under each group as children.
    JSONArray primaryArr = new JSONArray();
    if (hasPrimaryGroup) {
        for (Map.Entry<String,Map<String,String>> ge : primaryTree.entrySet()) {
            JSONObject g = new JSONObject();
            g.put("key",   ge.getKey());
            g.put("label", primaryGroupLabels.get(ge.getKey()));
            g.put("color", "#999");
            JSONArray kids = new JSONArray();
            for (Map.Entry<String,String> fe : ge.getValue().entrySet()) {
                JSONObject c = new JSONObject();
                c.put("key",   fe.getKey());
                c.put("label", fe.getValue());
                c.put("color", primaryColor.get(fe.getKey()));
                kids.add(c);
            }
            g.put("children", kids);
            primaryArr.add(g);
        }
    } else {
        for (Map.Entry<String,String> e : primaryColor.entrySet()) {
            JSONObject p = new JSONObject();
            p.put("key",   e.getKey());
            p.put("label", primaryLabels.get(e.getKey()));
            p.put("color", e.getValue());
            p.put("visible", true);
            primaryArr.add(p);
        }
    }
    JSONArray secArr = new JSONArray();
    if (hasSecondaryGroup) {
        for (Map.Entry<String,Map<String,String>> ge : secondaryTree.entrySet()) {
            JSONObject g = new JSONObject();
            g.put("key",   ge.getKey());
            g.put("label", secondaryGroupLabels.get(ge.getKey()));
            g.put("color", "#999");
            JSONArray kids = new JSONArray();
            for (Map.Entry<String,String> fe : ge.getValue().entrySet()) {
                JSONObject c = new JSONObject();
                c.put("key",   fe.getKey());
                c.put("label", fe.getValue());
                kids.add(c);
            }
            g.put("children", kids);
            secArr.add(g);
        }
    } else {
        for (String key : secondaryKeys) {
            JSONObject secObj = new JSONObject();
            secObj.put("key",   key);
            secObj.put("label", secondaryLbl.get(key));
            secObj.put("visible", true);
            secArr.add(secObj);
        }
    }

    JSONObject payload = new JSONObject();
    payload.put("events",   events);
    payload.put("primary",  primaryArr);
    payload.put("secondary", secArr);
    payload.put("primaryLabel",   primaryFilterLabel);
    payload.put("secondaryLabel", secLabel);
    JSONObject opts = new JSONObject();
    opts.put("defaultView", defaultView);
    opts.put("height",      strHeight);
    opts.put("readonly",    calReadOnly);
    opts.put("showLegend",  showLegend);
    opts.put("ctrlId",  ctrlId);
    opts.put("hasPrimary",   primaryFilterValueAttr.length() > 0);
    opts.put("hasPrimaryGroup",   hasPrimaryGroup);
    opts.put("hasSecondary", secondaryFilterValueAttr.length() > 0);
    opts.put("hasSecondaryGroup", hasSecondaryGroup);
    payload.put("options",  opts);

    String payloadJson  = payload.serialize().replace("</", "<\\/");
    String ctrlIdJs     = ctrlId.replaceAll("[^a-zA-Z0-9_]", "_");
%>

<%-- =============================================================
     Static assets (loaded once per page render via a page-scope flag
     so multiple controls on the same page don't double-load them).
     FullCalendar v6 ships index.global.js + index.css.
     ============================================================= --%>
<%
    if (pageContext.getAttribute("__mascal_libs") == null) {
        pageContext.setAttribute("__mascal_libs", "1");
%>
<!--<link  rel="stylesheet" href="<%=libPath%>/fullcalendar/index.css">-->
<link  rel="stylesheet" href="<%=ctx%>/webclient/css/calendarcontrol.css">
<script src="<%=libPath%>/fullcalendar/index.global.js"></script>
<%
    }
%>

<%-- =============================================================
     Inline data + container for this control instance.
     ============================================================= --%>
<script type="text/javascript">
    window.__MASCAL_DATA = window.__MASCAL_DATA || {};
    window.__MASCAL_DATA["<%=ctrlIdJs%>"] = <%=payloadJson%>;
</script>

<div id="<%=ctrlId%>" class="mascal-root<%= cssClass!=null && cssClass.length()>0 ? " "+cssClass : "" %>"
     data-mascal="<%=ctrlIdJs%>"
     data-mascal-readonly="<%=calReadOnly%>"
     style="height:<%=strHeight%>px;">

    <% if (showLegend) { %>
    <div class="mascal-legend" id="<%=ctrlId%>_legend">
    <h1 style="text-align: center; padding-bottom: 10px">Calendar Filters</h1>
        <div class="mascal-tabs">
            <button type="button" class="mascal-tab active" data-tab="people"><%= primaryFilterLabel %></button>
            <button type="button" class="mascal-tab" data-tab="secondary"
                    style="display:none;"><%= secLabel %></button>
        </div>
        <div class="mascal-legend-body">
            <ul class="mascal-legend-list mascal-tabpanel active" data-panel="people"></ul>
            <ul class="mascal-legend-list mascal-tabpanel" data-panel="secondary"></ul>
        </div>
    </div>
    <% } %>

    <div class="mascal-calendar" id="<%=ctrlId%>_cal"></div>
</div>

<script type="text/javascript" src="<%=ctx%>/webclient/javascript/calendarcontrol.js"></script>

<%
    } // end else (not designmode)
%>
<%@ include file="../common/componentfooter.jsp"%>
