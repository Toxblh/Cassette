/* Copyright 2026 Anton Palgunov
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


/**
 * A bin that does not pass its child's minimum width up: it asks for
 * ``min-width`` and clips the child if the child needs more. The window can
 * then get narrower than a layout that is about to be swapped for a compact
 * one (``PlayerBar.compact`` is set from the window size, so the wide layout
 * only ever sees a too-small allocation for one frame). The same idea as
 * ``Adw.BreakpointBin``, without breakpoints and their map/unmap churn.
 */
public class Cassette.ClipBin : Gtk.Widget {

    Gtk.Widget? _child = null;
    public Gtk.Widget? child {
        get {
            return _child;
        }
        set {
            if (_child == value) {
                return;
            }
            if (_child != null) {
                _child.unparent ();
            }
            _child = value;
            if (_child != null) {
                _child.set_parent (this);
            }
            queue_resize ();
        }
    }

    /** Minimum width reported to the parent, regardless of the child. */
    public int min_width { get; set; default = 0; }

    construct {
        overflow = Gtk.Overflow.HIDDEN;
        notify["min-width"].connect (queue_resize);
    }

    static construct {
        set_css_name ("clipbin");
    }

    public override Gtk.SizeRequestMode get_request_mode () {
        return _child != null ? _child.get_request_mode () : Gtk.SizeRequestMode.CONSTANT_SIZE;
    }

    public override void measure (
        Gtk.Orientation orientation,
        int for_size,
        out int minimum,
        out int natural,
        out int minimum_baseline,
        out int natural_baseline
    ) {
        minimum_baseline = -1;
        natural_baseline = -1;

        if (_child == null) {
            minimum = orientation == Gtk.Orientation.HORIZONTAL ? min_width : 0;
            natural = minimum;
            return;
        }

        if (orientation == Gtk.Orientation.HORIZONTAL) {
            int child_min, child_nat;
            _child.measure (orientation, for_size, out child_min, out child_nat, null, null);
            minimum = int.min (child_min, min_width);
            natural = int.max (child_nat, minimum);
        } else {
            // Height for the width the child will really get (never below its minimum).
            int width = for_size;
            if (width >= 0) {
                int child_min_width;
                _child.measure (Gtk.Orientation.HORIZONTAL, -1, out child_min_width, null, null, null);
                width = int.max (width, child_min_width);
            }
            _child.measure (orientation, width, out minimum, out natural, null, null);
        }
    }

    public override void size_allocate (int width, int height, int baseline) {
        if (_child == null) {
            return;
        }
        int child_min;
        _child.measure (Gtk.Orientation.HORIZONTAL, -1, out child_min, null, null, null);
        _child.allocate (int.max (width, child_min), height, baseline, null);
    }

    public override void dispose () {
        child = null;
        base.dispose ();
    }
}
