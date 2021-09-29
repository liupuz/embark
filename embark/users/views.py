import logging
import json


from django.http import HttpResponse
from django.shortcuts import redirect, render
from django.views.decorators.csrf import csrf_exempt
from django.views.decorators.http import require_http_methods

from django.contrib.auth import authenticate, login, logout
import django.contrib.messages as messages

from .models import User

logger = logging.getLogger('web')


@csrf_exempt
@require_http_methods(["GET", "POST"])
def signin(request):
    if request.method == "POST":
        logger.debug(request.POST)
        logger.debug(request.body)
        data = {k: v[0] for k, v in dict(request.POST).items()}
        logger.debug(data)
        try:
            try:
                body = json.loads(request.body.decode(encoding='UTF-8'))
            except json.JSONDecodeError:
                body = {k: v[0] for k, v in dict(request.POST).items()}
            try:
                username = body['email']
                password = body['password']
            except KeyError:
                logger.exception('Missing keys from data- Username and password')
                return HttpResponse("User data is invalid")

            logger.debug('Found user name and password')
            user = authenticate(request, username=username, password=password)
            if user is not None:
                logger.debug('User authenticated')
                login(request, user)
                logger.debug('User logged in')
                return redirect('embark-home')
            # else:
            logger.debug('User could not be authenticated')
            messages.info(request, "Invalid user data")
            return render(request, 'uploader/login.html', {'error_message': True})
        except Exception as error:
            logger.exception('Wide exception in Signup: %s', error)
            messages.info(request, "Invalid user data")
            return render(request, 'uploader/login.html', {'error_message': True})
    else:
        return render(request, 'login.html')


@csrf_exempt
@require_http_methods(["POST"])
def signup(request):
    if request.method == "POST":
        logger.debug(request.POST)
        logger.debug(request.body)
        data = {k: v[0] for k, v in dict(request.POST).items()}
        logger.debug(data)
        try:
            try:
                body = json.loads(request.body.decode(encoding='UTF-8'))
            except json.JSONDecodeError:
                body = {k: v[0] for k, v in dict(request.POST).items()}
            try:
                username = body['email']
                password = body['password']
                confirm_password = body['confirm_password']

                if password == confirm_password:
                    logger.debug('Passwords match. Creating user')
                    user = User.objects.create(username=username, email=username)
                    user.set_password(password)
                    user.save()
                    logger.debug('User created')
                else:
                    logger.debug('Passwords do not match')
                    return HttpResponse("Passwords do not match")

                user = authenticate(username=username, password=password)
                logger.debug('User authenticated')
                if user is not None:
                    login(request, user)
                    logger.debug('User logged in')
                    return HttpResponse("Signup complete. User Logged in")
                # else:
                return HttpResponse("Invalid signup data")

            except KeyError:
                logger.exception('Missing keys from data- Username, password, password_confirm')
                return HttpResponse("User data is invalid")
        except Exception as error:
            logger.exception('Wide exception in Signup: %s', error)
            return HttpResponse("Something went wrong when signing up the user")


@csrf_exempt
#@cache_control(no_cache=True, must_revalidate=True, no_store=True)
def signout(request):
    #request.session.flush()
    logger.debug("Logout user %s", request.user)
    logout(request)
    return render(request, 'uploader/login.html', {'error_message': True})