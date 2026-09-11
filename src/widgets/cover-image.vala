/* Copyright 2023-2024 Vladimir Vaskov
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <http://www.gnu.org/licenses/>.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */


using Cassette.Client;
using Gee;

[GtkTemplate (ui = "/space/rirusha/Cassette/ui/cover-image.ui")]
public sealed class Cassette.CoverImage : Gtk.Frame {

    [GtkChild]
    unowned Gtk.Image placeholder_image;
    [GtkChild]
    unowned Gtk.Stack stack;

    public CoverSize cover_size { get; set; default = CoverSize.BIG; }

    public HasCover yam_object { get; private set; }

    /**
     * Easy way to set both width and height of the cover widget.
     */
    public int image_widget_size { get; set; }

    construct {
        notify["cover-size"].connect (() => {
            switch (cover_size) {
                case CoverSize.SMALL:
                    placeholder_image.icon_size = Gtk.IconSize.NORMAL;
                    image_widget_size = 60;
                    add_css_class ("small-border-radius");
                    break;

                case CoverSize.BIG:
                    placeholder_image.icon_size = Gtk.IconSize.LARGE;
                    image_widget_size = 200;
                    remove_css_class ("small-border-radius");
                    break;

                default:
                    assert_not_reached ();
            }
        });
    }

    public void init_content (HasCover yam_object) {
        this.yam_object = yam_object;
        add_css_class ("card");
    }

    public void clear () {
        yam_object = null;
        remove_css_class ("card");
        reset_image ();
    }

    /** Drop whatever cover is shown and go back to the placeholder icon. */
    void reset_image () {
        for (var child = stack.get_first_child (); child != null; )
            {
                var next = child.get_next_sibling ();
                if (child != placeholder_image)
                    stack.remove (child);
                child = next;
            }

        stack.visible_child = placeholder_image;
    }

    /**
     * GdkPixbuf is straight RGBA, but the cairo renderer draws
     * premultiplied BGRA. Converting here once keeps every frame from
     * running a blocking conversion for each cover it draws.
     */
    public static Gdk.Texture texture_for_pixbuf (Gdk.Pixbuf pixbuf) {
        int width = pixbuf.get_width ();
        int height = pixbuf.get_height ();
        int channels = pixbuf.get_n_channels ();
        int source_stride = pixbuf.get_rowstride ();
        bool has_alpha = pixbuf.get_has_alpha ();
        unowned uint8[] source = pixbuf.get_pixels ();
        int stride = width * 4;
        var target = new uint8[stride * height];

        for (int y = 0; y < height; y++) {
            int source_row = y * source_stride;
            int target_row = y * stride;

            for (int x = 0; x < width; x++) {
                int si = source_row + x * channels;
                int ti = target_row + x * 4;
                uint8 r = source[si];
                uint8 g = source[si + 1];
                uint8 b = source[si + 2];
                uint8 a = has_alpha ? source[si + 3] : 255;

                target[ti] = (uint8) ((b * a) / 255);
                target[ti + 1] = (uint8) ((g * a) / 255);
                target[ti + 2] = (uint8) ((r * a) / 255);
                target[ti + 3] = a;
            }
        }

        return new Gdk.MemoryTexture (
            width, height, Gdk.MemoryFormat.B8G8R8A8_PREMULTIPLIED,
            new Bytes.take (target), stride
        );
    }

    public async void load_image () {
        assert (yam_object != null);

        /* The widget is reused (the player bar, recycled list rows): never
         * keep the previous track's cover while this one loads, and leave
         * the placeholder if it has no cover at all. */
        reset_image ();

        Gdk.Pixbuf? pixbuf_buffer = null;

        pixbuf_buffer = yield Cachier.get_image (yam_object, (int) cover_size);

        if (pixbuf_buffer != null) {
            var real_image = new Gtk.Image ();
            real_image.set_from_paintable (texture_for_pixbuf (pixbuf_buffer));

            bind_property (
                "image-widget-size",
                real_image,
                "width-request",
                GLib.BindingFlags.SYNC_CREATE
            );
            bind_property (
                "image-widget-size",
                real_image,
                "height-request",
                GLib.BindingFlags.SYNC_CREATE
            );
            bind_property (
                "image-widget-size",
                real_image,
                "pixel-size",
                GLib.BindingFlags.SYNC_CREATE
            );

            stack.add_child (real_image);

            stack.visible_child = real_image;
        }
    }
}
