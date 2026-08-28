from django.urls import path

from .views import MeView, RegisterView, login_obtain, token_refresh

urlpatterns = [
    path("register/", RegisterView.as_view(), name="register"),
    path("login/", login_obtain, name="login"),
    path("refresh/", token_refresh, name="refresh"),
    path("me/", MeView.as_view(), name="me"),
]
