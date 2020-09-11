# Docker-in-Docker Drone plugin

This is a plugin for **Drone 0.8** that is aimed mainly at enabling [Testcontainers](https://www.testcontainers.org) to be used during CI build/test steps. 
Due to Drone's architecture, Docker-in-Docker is often the most practical way to run builds that require a Docker daemon.

This plugin:

* Is based upon an Docker-in-Docker image
* Includes a startup script that:
	* Starts a nested docker daemon
	* Optionally starts a pull of required images (in parallel with your build, so as to reduce overall time spent waiting for images to be pulled)
	* Starts a specified build container inside the Docker-in-Docker context, containing your source code and with a docker socket available to it

## Prerequisites

Either:

* (Drone 0.8): To enable on a per-repository basis, enable the *Trusted* setting for the repository. *Or*
* (Drone 0.8): To enable this plugin globally in your Drone instance, add the image name to the `DRONE_ESCALATE` environment variable that the Drone process runs under.

## Usage/Migration (Drone 0.8)

Modify the `build` step of the pipeline to resemble:

```yaml
steps:
  - name: build
    image: quay.io/testcontainers/dind-drone-plugin
    environment:
      CI_WORKSPACE: "/drone/src"
    settings:
      # This specifies the command that should be executed to perform build, test and
      #  integration tests. Not to be confused with Drone's `command`:
      cmd: sleep 5 && ./gradlew clean check --info
      # This image will run the cmd with your build steps
      build_image: adoptopenjdk:14-openj9
      # Not mandatory; enables pre-fetching of images in parallel with the build, so may save 
      #  time:
      prefetch_images:
        - "redis:4.0.6"
      # Not mandatory; sets up image name 'aliases' by pulling from one registry and tagging
      #  as a different name. Intended as a simplistic mechanism for using a private registry 
      #  rather than Docker Hub for a known set of images. Accepts a dictionary of
      #  private registry image name to the Docker Hub image that it is a substitute for.
      #  Note that all images are pulled synchronously before the build starts, so this is
      #  inefficient if any unnecessary images are listed.
      image_aliases:
        someregistry.com/redis:4.0.6: redis:4.0.6
      volumes:
        - name: dockersock
          path: /var/run

# Specify docker:dind as a service
services:
- name: docker
  image: docker:dind
  privileged: true
  volumes:
  - name: dockersock
    path: /var/run

volumes:
- name: dockersock
  temp: {}
```

When migrating to use this plugin from an ordinary build step, note that:

* `commands` should be changed to `cmd`. Note that _commas_ are not supported within `cmd` lines due to the way these are passed in between Drone and this plugin.
* `image` should be changed to `build_image`
* `prefetch_images` is optional, but recommended. This specifies a list of images that should be pulled in parallel with your build process, thus saving some time.

## Extending

Users with custom requirements can build a new image using this as a base image.

This image uses hook scripts, if present, to perform custom actions. Such scripts may be placed as executable files in any of `/dind-drone-plugin/hooks/{pre_daemon_start,post_daemon_start,pre_run,post_run}`, depending on which phase they are required to run in.

Some initial hook scripts already exist, which should be overwritten or removed if needed.

## Copyright

This repository contains code which was mainly developed at [Skyscanner](https://www.skyscanner.net/jobs/), and is licenced under the [Apache 2.0 Licence](LICENSE).

(c) 2017-2020 Skyscanner Ltd.
