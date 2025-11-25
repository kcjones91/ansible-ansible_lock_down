FROM registry.access.redhat.com/ubi8/ubi

# Update container
RUN dnf update -y

# Install packages
RUN yum -y install \
      openssh-server \
      sudo \
      python3 \
      iproute \
      hostname \
      git \
    && yum clean all

# Create ansible user with passwordless sudo
RUN useradd -m -s /bin/bash ansible && \
    echo 'ansible ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/ansible && \
    chmod 440 /etc/sudoers.d/ansible && \
    echo "ansible:password" | chpasswd

# Generate host keys so sshd actually stays running
RUN ssh-keygen -A

# Basic SSHD config
RUN mkdir -p /var/run/sshd && \
    sed -i 's/#PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config

# Quick build-time sanity check that sshd can bind to 22
RUN /usr/sbin/sshd && \
    sleep 2 && \
    bash -c 'echo > /dev/tcp/127.0.0.1/22' || (echo "SSH port 22 NOT listening at build time" && exit 1)

EXPOSE 22

# At runtime, sshd is PID 1 and stays up
CMD ["/usr/sbin/sshd", "-D", "-e"]
