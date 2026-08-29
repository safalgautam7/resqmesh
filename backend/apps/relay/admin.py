from django.contrib import admin

from .models import RelayDevice, RelayMessage


class RelayMessageInline(admin.TabularInline):
    model = RelayMessage.carried_by.through
    extra = 0


@admin.register(RelayMessage)
class RelayMessageAdmin(admin.ModelAdmin):
    list_display = (
        "message_id",
        "source_node",
        "hop_count",
        "max_hops",
        "delivery_status",
        "synced_to_server",
        "created_at",
    )
    list_filter = ("delivery_status", "synced_to_server")
    readonly_fields = ("created_at",)


@admin.register(RelayDevice)
class RelayDeviceAdmin(admin.ModelAdmin):
    list_display = ("name", "online", "last_seen")
