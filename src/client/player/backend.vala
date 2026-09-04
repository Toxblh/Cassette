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
 * One player of one stream. Everything that knows about the queue,
 * shuffle and preloading lives in Player and is invisible to the backend.
 *
 * An Object rather than an interface because Player binds volume and
 * mute through bind_property, which needs GObject properties.
 */
public abstract class Cassette.Client.Player.PlayerBackend : Object {

    /** Set by Player through bind_property. */
    public double volume { get; set; default = 1.0; }

    public bool mute { get; set; default = false; }

    /**
     * Current position. Duration is not needed: Player takes it from
     * the track metadata.
     */
    public abstract int64 position_ms { get; }

    /** null unloads the current stream. */
    public abstract void set_uri (string? uri);

    public abstract void play ();

    public abstract void pause ();

    public abstract void stop ();

    public abstract void seek (int64 ms);

    /** Stream finished on its own. Player calls next_natural (). */
    public signal void eos ();

    /**
     * Playback failed. An expired signed stream URL produces this, not
     * eos; without it the player would silently hang on the track.
     */
    public signal void error (string message);

    /**
     * The platform asks to pause (audio focus lost to a call or another
     * player). Player pauses so the UI stays in sync.
     */
    public signal void suspended ();

    /** Audio focus is back after a transient loss. Player resumes. */
    public signal void resumed ();
}
