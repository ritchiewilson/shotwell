 /* Copyright 2009-2012 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */

private class PositionMarker : Object {
    private MapWidget map_widget;
    protected PositionMarker.from_group(MapWidget map_widget) {
        this.map_widget = map_widget;
    }
    public PositionMarker(MapWidget map_widget, DataView view, Champlain.Marker marker) {
        this.map_widget = map_widget;
        this.view = view;
        this.marker = marker;
    }
    public bool selected {
        get {
            return marker.get_selected();
        }
        set {
            marker.set_selected(value);
            if (!(marker is Champlain.Point)) {
                // first child of the marker is a ClutterGroup which contains the texture
                var t = (Clutter.Texture) marker.get_first_child().get_first_child();
                if (value) {
                    t.set_cogl_texture(map_widget.marker_selected_cogl_texture);
                } else {
                    t.set_cogl_texture(map_widget.marker_cogl_texture);
                }
            }
        }
    }

    public Champlain.Marker marker { get; protected set; }
    // Geo lookup
    // public string location_country { get; set; }
    // public string location_city { get; set; }
    public unowned DataView view { get; protected set; }
}

private class MarkerGroup : PositionMarker {
    private Gee.Set<PositionMarker> markers = new Gee.HashSet<PositionMarker>();
    public MarkerGroup(MapWidget map_widget, PositionMarker first_marker) {
        base.from_group(map_widget);
        markers.add(first_marker);
        // use the first markers internal texture as the group's
        marker = first_marker.marker;
        view = first_marker.view;
    }
    public void add_marker(PositionMarker marker) {
        markers.add(marker);
    }
    public Gee.Set<PositionMarker> get_markers() {
        return markers;
    }
}

private class MapWidget : GtkChamplain.Embed {
    private const uint DEFAULT_ZOOM_LEVEL = 8;
    private const long MARKER_GROUP_RASTER_WIDTH = 30l;

    private static MapWidget instance = null;

    private Champlain.View map_view = null;
    private uint last_zoom_level = DEFAULT_ZOOM_LEVEL;
    private Champlain.Scale map_scale = new Champlain.Scale();
    private Champlain.MarkerLayer marker_layer = new Champlain.MarkerLayer();
    private Gee.Map<DataView, PositionMarker> position_markers =
        new Gee.HashMap<DataView, PositionMarker>();
    private Gee.TreeMap<long, Gee.TreeMap<long, MarkerGroup>> marker_groups_tree =
        new Gee.TreeMap<long, Gee.TreeMap<long, MarkerGroup>>();
    private Gee.Collection<MarkerGroup> marker_groups = new Gee.LinkedList<MarkerGroup>();
    private unowned Page page = null;

    public Cogl.Handle marker_cogl_texture { get; private set; }
    public Cogl.Handle marker_selected_cogl_texture { get; private set; }

    public static MapWidget get_instance() {
        if (instance == null)
            instance = new MapWidget();
        return instance;
    }

    public void set_page(Page page) {
        this.page = page;
    }

    public void setup_map() {
        // add scale to bottom left corner of the map
        map_view = get_view();
        map_view.add_layer(marker_layer);
        map_scale.x_align = Clutter.ActorAlign.START;
        map_scale.y_align = Clutter.ActorAlign.END;
        map_scale.connect_view(map_view);
        map_view.add(map_scale);

        map_view.set_zoom_on_double_click(false);
        map_view.layer_relocated.connect(map_relocated_handler);

        button_press_event.connect(map_zoom_handler);
        set_size_request(200, 200);

        // Load gdk pixbuf via Resources class
        Gdk.Pixbuf gdk_marker = Resources.get_icon(Resources.ICON_GPS_MARKER);
        Gdk.Pixbuf gdk_marker_selected = Resources.get_icon(Resources.ICON_GPS_MARKER_SELECTED);
        try {
            // this is what GtkClutter.Texture.set_from_pixmap does
            var tex = new Clutter.Texture();
            tex.set_from_rgb_data(gdk_marker.get_pixels(),
                                            gdk_marker.get_has_alpha(),
                                            gdk_marker.get_width(),
                                            gdk_marker.get_height(),
                                            gdk_marker.get_rowstride(),
                                            gdk_marker.get_has_alpha() ? 4 : 3,
                                            Clutter.TextureFlags.NONE);
            marker_cogl_texture = tex.get_cogl_texture();
            tex.set_from_rgb_data(gdk_marker_selected.get_pixels(),
                                            gdk_marker_selected.get_has_alpha(),
                                            gdk_marker_selected.get_width(),
                                            gdk_marker_selected.get_height(),
                                            gdk_marker_selected.get_rowstride(),
                                            gdk_marker_selected.get_has_alpha() ? 4 : 3,
                                            Clutter.TextureFlags.NONE);
            marker_selected_cogl_texture = tex.get_cogl_texture();
        } catch (GLib.Error e) {
            // Fall back to the generic champlain marker
            marker_cogl_texture = null;
            marker_selected_cogl_texture = null;
        }
    }

    public void clear() {
        marker_layer.remove_all();
        marker_groups_tree.clear();
        marker_groups.clear();
        position_markers.clear();
    }

    public void add_position_marker(DataView view) {
        DataSource view_source = view.get_source();
        if (!(view_source is Positionable)) {
            return;
        }
        Positionable p = (Positionable) view_source;
        GpsCoords gps_coords = p.get_gps_coords();
        if (gps_coords.has_gps <= 0) {
            return;
        }

        // rasterize coords
        long x = (long)(map_view.longitude_to_x(gps_coords.longitude) / MARKER_GROUP_RASTER_WIDTH);
        long y = (long)(map_view.latitude_to_y(gps_coords.latitude) / MARKER_GROUP_RASTER_WIDTH);
        PositionMarker position_marker = create_position_marker(view);
        var yg = marker_groups_tree.get(x);
        if (yg == null) {
            // y group doesn't exist, initialize it
            yg = new Gee.TreeMap<long, MarkerGroup>();
            var mg = new MarkerGroup(this, position_marker);
            yg.set(y, mg);
            marker_groups.add(mg);
            marker_groups_tree.set(x, yg);
            add_marker(mg.marker);
        } else {
            var mg = yg.get(y);
            if (mg == null) {
                // first marker in this group
                mg = new MarkerGroup(this, position_marker);
                yg.set(y, mg);
                marker_groups.add(mg);
                add_marker(mg.marker);
            } else {
                // marker group already exists
                mg.add_marker(position_marker);
            }
        }

        position_markers.set(view, position_marker);

        /*
        float x,y;
        position_marker.marker.get_position(out x, out y);
        stdout.printf("loc: %f\t%f\n", x, y);
        */
    }

    public void show_position_markers() {
        if (!position_markers.is_empty) {
            if (map_view.get_zoom_level() < DEFAULT_ZOOM_LEVEL) {
                map_view.set_zoom_level(DEFAULT_ZOOM_LEVEL);
            }
            Champlain.BoundingBox bbox = marker_layer.get_bounding_box();
            map_view.ensure_visible(bbox, true);
        }
    }

    private PositionMarker create_position_marker(DataView view) {
        DataSource data_source = view.get_source();
        Positionable p = (Positionable) data_source;
        GpsCoords gps_coords = p.get_gps_coords();
        assert(gps_coords.has_gps > 0);
        Champlain.Marker champlain_marker;
        if (marker_cogl_texture == null) {
            // Fall back to the generic champlain marker
            champlain_marker = new Champlain.Point.full(12, { red:10, green:10, blue:255, alpha:255 });
        } else {
            champlain_marker = new Champlain.Marker(); // TODO: deprecated, switch to Champlain.Marker once libchamplain-0.12.4 is used
            var t = new Clutter.Texture();
            t.set_cogl_texture(marker_cogl_texture);
            champlain_marker.add(t);
        }
        champlain_marker.set_pivot_point(0.5f, 0.5f); // set center of marker
        champlain_marker.set_location(gps_coords.latitude, gps_coords.longitude);
        return new PositionMarker(this, view, champlain_marker);
    }

    private void add_marker(Champlain.Marker marker) {
        marker_layer.add_marker(marker);
    }

    private bool map_zoom_handler(Gdk.EventButton event) {
        if (event.type == Gdk.EventType.2BUTTON_PRESS) {
            if (event.button == 1 || event.button == 3) {
                double lat = map_view.y_to_latitude(event.y);
                double lon = map_view.x_to_longitude(event.x);
                if (event.button == 1) {
                    map_view.zoom_in();
                } else {
                    map_view.zoom_out();
                }
                map_view.center_on(lat, lon);
                return true;
            }
        }
        return false;
    }

    private void map_relocated_handler() {
        uint new_zoom_level = map_view.get_zoom_level();
        if (last_zoom_level != new_zoom_level) {
            rezoom();
            last_zoom_level = new_zoom_level;
        }
    }

    private void rezoom() {
        marker_groups_tree.clear();
        Gee.Collection<MarkerGroup> marker_groups_new = new Gee.LinkedList<MarkerGroup>();
        foreach (var marker_group in marker_groups) {
            marker_layer.remove_marker(marker_group.marker);
            foreach (var position_marker in marker_group.get_markers()) {
                // rasterize coords
                long x = (long)(map_view.longitude_to_x(position_marker.marker.longitude) / MARKER_GROUP_RASTER_WIDTH);
                long y = (long)(map_view.latitude_to_y(position_marker.marker.latitude) / MARKER_GROUP_RASTER_WIDTH);
                var yg = marker_groups_tree.get(x);
                if (yg == null) {
                    // y group doesn't exist, initialize it
                    yg = new Gee.TreeMap<long, MarkerGroup>();
                    var mg = new MarkerGroup(this, position_marker);
                    yg.set(y, mg);
                    marker_groups_new.add(mg);
                    marker_groups_tree.set(x, yg);
                    add_marker(mg.marker);
                } else {
                    var mg = yg.get(y);
                    if (mg == null) {
                        // first marker -> create new group
                        mg = new MarkerGroup(this, position_marker);
                        yg.set(y, mg);
                        marker_groups_new.add(mg);
                        add_marker(mg.marker);
                    } else {
                        // marker group already exists
                        mg.add_marker(position_marker);
                    }
                }
            }
        }
        marker_groups = marker_groups_new;
    }
}
