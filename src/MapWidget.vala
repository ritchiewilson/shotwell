 /* Copyright 2009-2012 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution.
 */


private class MapWidget : GtkChamplain.Embed {
    private const uint DEFAULT_ZOOM_LEVEL = 8;

    private static MapWidget instance = null;

    private Champlain.View map_view = null;
    private Champlain.Scale map_scale = new Champlain.Scale();
    private Champlain.MarkerLayer marker_layer = new Champlain.MarkerLayer();
    public Cogl.Handle marker_cogl_texture { get; private set; }

    public static MapWidget get_instance() {
        if (instance == null)
            instance = new MapWidget();
        return instance;
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

        button_press_event.connect(map_zoom_handler);
        set_size_request(200, 200);

        // Load gdk pixbuf via Resources class
        Gdk.Pixbuf gdk_marker = Resources.get_icon(Resources.ICON_GPS_MARKER);
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
        } catch (GLib.Error e) {
            // Fall back to the generic champlain marker
            marker_cogl_texture = null;
        }
    }

    public void clear() {
        marker_layer.remove_all();
    }

    public void add_position_marker(DataView view) {
        clear();
        DataSource view_source = view.get_source();
        if (!(view_source is Positionable)) {
            return;
        }
        Positionable p = (Positionable) view_source;
        GpsCoords gps_coords = p.get_gps_coords();
        if (gps_coords.has_gps <= 0) {
            return;
        }
        
        Champlain.Marker marker = create_champlain_marker(view);
        marker_layer.add_marker(marker);
    }

    public void show_position_markers() {
        if (marker_layer.get_markers().length() != 0) {
            if (map_view.get_zoom_level() < DEFAULT_ZOOM_LEVEL) {
                map_view.set_zoom_level(DEFAULT_ZOOM_LEVEL);
            }
            Champlain.BoundingBox bbox = marker_layer.get_bounding_box();
            map_view.ensure_visible(bbox, true);
        }
    }

    private Champlain.Marker create_champlain_marker(DataView view) {
        DataSource data_source = view.get_source();
        Positionable p = (Positionable) data_source;
        GpsCoords gps_coords = p.get_gps_coords();
        assert(gps_coords.has_gps > 0);
        Champlain.Marker champlain_marker;
        if (marker_cogl_texture == null) {
            // Fall back to the generic champlain marker
            champlain_marker = new Champlain.Point.full(12, { red:10, green:10, blue:255, alpha:255 });
        } else {
            champlain_marker = new Champlain.CustomMarker(); // TODO: deprecated, switch to Champlain.Marker once libchamplain-0.12.4 is used
            var t = new Clutter.Texture();
            t.set_cogl_texture(marker_cogl_texture);
            champlain_marker.add(t);
        }
        champlain_marker.set_pivot_point(0.5f, 0.5f); // set center of marker
        champlain_marker.set_location(gps_coords.latitude, gps_coords.longitude);
        return champlain_marker;
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
}
