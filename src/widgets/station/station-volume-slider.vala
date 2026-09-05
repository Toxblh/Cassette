/* Copyright 2023-2024 Anton Palgunov
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

namespace Cassette {

    public class StationVolumeSlider : Gtk.Box {

        public signal void volume_changed (double volume);

        private Gtk.Button mute_button;
        private Gtk.Scale volume_scale;
        private Gtk.Label percent_label;
        private Gtk.Adjustment adjustment;

        private bool _muted = false;
        private double _last_volume = 0.5;

        private double _volume = 0.5;
        public double volume {
            get { return _volume; }
            set {
                _volume = value.clamp (0.0, 1.0);
                if (!_muted) {
                    adjustment.value = _volume;
                    update_percent_label (_volume);
                }
                update_icon ();
            }
        }

        construct {
            orientation = Gtk.Orientation.HORIZONTAL;
            spacing = 4;
            valign = Gtk.Align.CENTER;

            mute_button = new Gtk.Button.from_icon_name ("audio-volume-high-symbolic") {
                css_classes = { "flat", "circular" },
                tooltip_text = _("Mute")
            };
            mute_button.clicked.connect (toggle_mute);
            append (mute_button);

            adjustment = new Gtk.Adjustment (0.5, 0.0, 1.0, 0.05, 0.1, 0.0);
            volume_scale = new Gtk.Scale (Gtk.Orientation.HORIZONTAL, adjustment) {
                hexpand = true,
                width_request = 120,
                draw_value = false,
                tooltip_text = _("Volume")
            };
            volume_scale.change_value.connect (on_scale_change_value);
            append (volume_scale);

            percent_label = new Gtk.Label ("50%") {
                width_chars = 4,
                xalign = 1.0f,
                css_classes = { "caption" }
            };
            append (percent_label);
        }

        private bool on_scale_change_value (Gtk.ScrollType scroll, double new_value) {
            double clamped = new_value.clamp (0.0, 1.0);
            _volume = clamped;
            _last_volume = clamped;
            _muted = false;
            update_percent_label (clamped);
            update_icon ();
            volume_changed (clamped);
            return false;
        }

        private void toggle_mute () {
            if (_muted) {
                _muted = false;
                adjustment.value = _last_volume;
                _volume = _last_volume;
                update_percent_label (_last_volume);
                volume_changed (_last_volume);
            } else {
                _last_volume = _volume;
                _muted = true;
                adjustment.value = 0.0;
                update_percent_label (0.0);
                volume_changed (0.0);
            }
            update_icon ();
        }

        private void update_icon () {
            double effective = _muted ? 0.0 : _volume;

            if (effective <= 0.0) {
                mute_button.icon_name = "audio-volume-muted-symbolic";
                mute_button.tooltip_text = _("Unmute");
            } else if (effective < 0.33) {
                mute_button.icon_name = "audio-volume-low-symbolic";
                mute_button.tooltip_text = _("Mute");
            } else if (effective < 0.66) {
                mute_button.icon_name = "audio-volume-medium-symbolic";
                mute_button.tooltip_text = _("Mute");
            } else {
                mute_button.icon_name = "audio-volume-high-symbolic";
                mute_button.tooltip_text = _("Mute");
            }
        }

        private void update_percent_label (double val) {
            percent_label.label = "%d%%".printf ((int) Math.round (val * 100.0));
        }

        public void set_volume_silent (double new_volume) {
            _volume = new_volume.clamp (0.0, 1.0);
            if (!_muted) {
                adjustment.value = _volume;
                update_percent_label (_volume);
            }
            update_icon ();
        }
    }
}
