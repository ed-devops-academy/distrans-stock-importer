FROM mcr.microsoft.com/powershell

RUN apt update && \
    apt install git -y

RUN mkdir /project

WORKDIR /project

VOLUME ["/project"]

CMD [ "tail", "-f", "/dev/null" ]