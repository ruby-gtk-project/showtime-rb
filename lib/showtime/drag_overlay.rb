# frozen_string_literal: true

require "adwaita"

module Showtime
  # DragOverlay is the port of upstream's showtime/widgets/drag_overlay.py,
  # which is itself Loupe's drag overlay rewritten in PyGObject:
  # https://gitlab.gnome.org/GNOME/loupe/-/blob/d66dd0f/src/widgets/drag_overlay.rs
  #
  # A bin with an overlay inside it: the usual content as the overlay's child,
  # and a crossfading revealer on top carrying whatever should be shown while a
  # drag is over the window. The revealer follows the drop target's
  # `current-drop` property, so the highlight appears and disappears with the
  # drag itself and nothing has to track it.
  #
  # Upstream declares `child`, `overlayed` and `drop_target` as GObject
  # properties so the Blueprint template can set them; here they are plain
  # accessors, which is what the property pairs amount to.
  # Upstream also gives the widget its own CSS node name,
  # "showtime-drag-overlay". That is a class-level call in GTK4
  # (gtk_widget_class_set_css_name) and the Ruby bindings expose only the
  # getter, so the node keeps the name it inherits — nothing in
  # showtime/gtk/style.css selects on it, the drag styling hangs off the
  # `.drop-widget` and `.showtime-dragging-area-highlight` classes the window
  # sets instead.
  class DragOverlay < Adwaita::Bin
    def build
      tap do
        overlay.tap do |over|
          over.set_parent(self)
          over.add_overlay(revealer)
        end
      end
    end

    # The usual content.
    def child = overlay.child

    def child=(widget)
      overlay.child = widget
    end

    # The widget overlayed when dragging over the child.
    def overlayed = revealer.child

    def overlayed=(widget)
      revealer.child = widget
    end

    attr_reader :drop_target

    # Reveals the overlay for as long as a drop is in progress over
    # `target`. Upstream connects the same `notify::current-drop` handler.
    def drop_target=(target)
      @drop_target = target
      if target
        target.signal_connect("notify::current-drop") do
          revealer.reveal_child = !target.current_drop.nil?
        end
      end
    end

    def overlay = @overlay ||= Gtk::Overlay.new

    def revealer
      @revealer ||= Gtk::Revealer.new.tap do |rev|
        rev.can_target = false
        rev.transition_type = :crossfade
        rev.reveal_child = false
      end
    end
  end
end
