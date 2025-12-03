IMAGE ?= project3-app
TAG ?= $(shell git rev-parse --short HEAD)

.PHONY: test build run push

test:
	pytest -q

build:
	docker build -t $(IMAGE):$(TAG) .

run:
	docker run -p 8000:8000 $(IMAGE):$(TAG)

push:
	docker push $(IMAGE):$(TAG)
