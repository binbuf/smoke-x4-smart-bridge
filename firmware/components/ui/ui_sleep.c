#include "ui_sleep.h"

#include <stddef.h>

void ui_view_init(ui_view_t *view, ui_page_t page, uint16_t timeout_s,
                  uint64_t now_ms) {
    if (view == NULL) {
        return;
    }
    view->page = (page < UI_PAGE_COUNT) ? page : UI_PAGE_PROBES;
    view->asleep = false;
    view->timeout_s = timeout_s;
    view->last_activity_ms = now_ms;
}

void ui_view_activity(ui_view_t *view, uint64_t now_ms) {
    if (view == NULL) {
        return;
    }
    view->last_activity_ms = now_ms;
}

ui_page_t ui_view_next_page(ui_view_t *view, bool billows_visible) {
    if (view == NULL) {
        return UI_PAGE_PROBES;
    }
    for (unsigned step = 0; step < UI_PAGE_COUNT; step++) {
        view->page = (ui_page_t)((view->page + 1u) % UI_PAGE_COUNT);
        if (view->page != UI_PAGE_BILLOWS || billows_visible) {
            break;
        }
    }
    return view->page;
}

void ui_view_set_page(ui_view_t *view, ui_page_t page) {
    if (view == NULL || page >= UI_PAGE_COUNT) {
        return;
    }
    view->page = page;
}

bool ui_view_tick(ui_view_t *view, uint64_t now_ms) {
    if (view == NULL || view->asleep || view->timeout_s == UI_TIMEOUT_NEVER) {
        return false;
    }
    uint64_t timeout_ms = (uint64_t)view->timeout_s * 1000u;
    if (now_ms < view->last_activity_ms) {
        /* A monotonic source should never do this; restart rather than sleep. */
        view->last_activity_ms = now_ms;
        return false;
    }
    if (now_ms - view->last_activity_ms >= timeout_ms) {
        view->asleep = true;
        return true;
    }
    return false;
}

bool ui_view_wake(ui_view_t *view, uint64_t now_ms) {
    if (view == NULL) {
        return false;
    }
    bool was_asleep = view->asleep;
    view->asleep = false;
    view->last_activity_ms = now_ms;
    return was_asleep;
}

uint64_t ui_view_next_tick_ms(const ui_view_t *view, uint64_t now_ms) {
    if (view == NULL || view->asleep || view->timeout_s == UI_TIMEOUT_NEVER) {
        return UINT64_MAX;
    }
    uint64_t timeout_ms = (uint64_t)view->timeout_s * 1000u;
    uint64_t elapsed = now_ms > view->last_activity_ms
                           ? now_ms - view->last_activity_ms
                           : 0u;
    if (elapsed >= timeout_ms) {
        return 0u;
    }
    return timeout_ms - elapsed;
}
