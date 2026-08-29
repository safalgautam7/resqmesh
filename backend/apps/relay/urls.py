from django.urls import path

from .views import relay_messages

urlpatterns = [
    path("messages/", relay_messages, name="relay-messages"),
]