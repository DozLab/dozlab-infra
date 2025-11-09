"""
Dozlab Session Manager - Python Example

This example shows how to create lab sessions using the Kubernetes Python client.
It reads the lab-pod-with-sidecar.yaml template and replaces variables programmatically.

Prerequisites:
    pip install kubernetes pyyaml

Usage:
    python create_session.py --session-id my-session-123 --user-id alice \\
        --rootfs-url https://example.com/dozlab-k8s.ext4
"""

import os
import sys
import yaml
import secrets
import argparse
from string import Template
from kubernetes import client, config
from kubernetes.client.rest import ApiException


class DozlabSessionManager:
    """Manages Dozlab lab sessions via Kubernetes API"""

    def __init__(self, namespace="default"):
        """
        Initialize the session manager

        Args:
            namespace: Kubernetes namespace to create resources in
        """
        # Load kubeconfig (from ~/.kube/config or in-cluster config)
        try:
            config.load_incluster_config()
        except config.ConfigException:
            config.load_kube_config()

        self.namespace = namespace
        self.core_v1 = client.CoreV1Api()

        # Load template from lab-pod-with-sidecar.yaml
        template_path = os.path.join(
            os.path.dirname(__file__),
            "../../lab-pod-with-sidecar.yaml"
        )
        with open(template_path, 'r') as f:
            self.template = f.read()

    def create_session(self, session_id, user_id, rootfs_url, **kwargs):
        """
        Create a new lab session

        Args:
            session_id: Unique identifier for this session
            user_id: User identifier for tracking
            rootfs_url: URL to the rootfs image (dozlab-k8s.ext4 or dozlab-vm.ext4)
            **kwargs: Optional parameters:
                - vscode_password: VS Code password (auto-generated if not provided)
                - vm_cpu: Number of CPUs for VM (default: 1)
                - vm_memory: Memory in MB for VM (default: 1024)
                - disk_size: Rootfs disk size (default: 4G)
                - terminal_image: Terminal sidecar image
                - vm_memory_limit: Container memory limit (default: 2Gi)
                - vm_cpu_limit: Container CPU limit (default: 1500m)
                - vm_memory_request: Container memory request (default: 1Gi)
                - vm_cpu_request: Container CPU request (default: 500m)
                - kernel_size_limit: Kernel volume size (default: 2Gi)
                - vm_data_size_limit: VM data volume size (default: 5Gi)
                - vscode_data_size_limit: VS Code data volume size (default: 1Gi)

        Returns:
            dict: Created resources (pod, service, secret)
        """
        # Generate secure password if not provided
        vscode_password = kwargs.get('vscode_password') or self._generate_password()

        # Prepare variable substitutions
        variables = {
            'SESSION_ID': session_id,
            'USER_ID': user_id,
            'ROOTFS_IMAGE_URL': rootfs_url,
            'VSCODE_PASSWORD': vscode_password,
            'DISK_SIZE': kwargs.get('disk_size', '4G'),
            'VM_CPU': str(kwargs.get('vm_cpu', 1)),
            'VM_MEMORY': str(kwargs.get('vm_memory', 1024)),
            'TERMINAL_IMAGE': kwargs.get('terminal_image', 'dozman99/dozlab-terminal:latest'),
            'VM_MEMORY_LIMIT': kwargs.get('vm_memory_limit', '2Gi'),
            'VM_CPU_LIMIT': kwargs.get('vm_cpu_limit', '1500m'),
            'VM_MEMORY_REQUEST': kwargs.get('vm_memory_request', '1Gi'),
            'VM_CPU_REQUEST': kwargs.get('vm_cpu_request', '500m'),
            'KERNEL_SIZE_LIMIT': kwargs.get('kernel_size_limit', '2Gi'),
            'VM_DATA_SIZE_LIMIT': kwargs.get('vm_data_size_limit', '5Gi'),
            'VSCODE_DATA_SIZE_LIMIT': kwargs.get('vscode_data_size_limit', '1Gi'),
        }

        # Replace variables in template
        manifest = Template(self.template).safe_substitute(variables)

        # Parse YAML documents
        resources = list(yaml.safe_load_all(manifest))

        # Create resources
        created = {}

        for resource in resources:
            if not resource:
                continue

            kind = resource.get('kind')
            metadata = resource.get('metadata', {})
            name = metadata.get('name')

            try:
                if kind == 'Pod':
                    pod = self.core_v1.create_namespaced_pod(
                        namespace=self.namespace,
                        body=resource
                    )
                    created['pod'] = pod
                    print(f"✓ Created Pod: {name}")

                elif kind == 'Service':
                    service = self.core_v1.create_namespaced_service(
                        namespace=self.namespace,
                        body=resource
                    )
                    created['service'] = service
                    print(f"✓ Created Service: {name}")

                elif kind == 'Secret':
                    secret = self.core_v1.create_namespaced_secret(
                        namespace=self.namespace,
                        body=resource
                    )
                    created['secret'] = secret
                    print(f"✓ Created Secret: {name}")

            except ApiException as e:
                print(f"✗ Failed to create {kind} {name}: {e.reason}")
                # Cleanup on failure
                self.delete_session(session_id)
                raise

        # Print access information
        print("\n" + "="*70)
        print(f"🚀 Lab Session Created: {session_id}")
        print("="*70)
        print(f"User ID: {user_id}")
        print(f"Rootfs: {rootfs_url}")
        print(f"VS Code Password: {vscode_password}")
        print(f"\nAccess via port-forward:")
        print(f"  kubectl port-forward lab-session-{session_id} 8080:8080 8081:8081")
        print(f"\nThen open:")
        print(f"  VS Code:  http://localhost:8080")
        print(f"  Terminal: http://localhost:8081")
        print("="*70)

        return created

    def delete_session(self, session_id):
        """
        Delete a lab session and all associated resources

        Args:
            session_id: Session identifier
        """
        pod_name = f"lab-session-{session_id}"
        service_name = f"lab-service-{session_id}"
        secret_name = f"lab-session-{session_id}-secrets"

        deleted = []

        # Delete Pod
        try:
            self.core_v1.delete_namespaced_pod(
                name=pod_name,
                namespace=self.namespace
            )
            deleted.append(f"Pod: {pod_name}")
        except ApiException as e:
            if e.status != 404:
                print(f"Warning: Failed to delete pod: {e.reason}")

        # Delete Service
        try:
            self.core_v1.delete_namespaced_service(
                name=service_name,
                namespace=self.namespace
            )
            deleted.append(f"Service: {service_name}")
        except ApiException as e:
            if e.status != 404:
                print(f"Warning: Failed to delete service: {e.reason}")

        # Delete Secret
        try:
            self.core_v1.delete_namespaced_secret(
                name=secret_name,
                namespace=self.namespace
            )
            deleted.append(f"Secret: {secret_name}")
        except ApiException as e:
            if e.status != 404:
                print(f"Warning: Failed to delete secret: {e.reason}")

        if deleted:
            print(f"✓ Deleted session {session_id}:")
            for item in deleted:
                print(f"  - {item}")
        else:
            print(f"✗ Session {session_id} not found")

    def list_sessions(self):
        """
        List all active lab sessions

        Returns:
            list: List of session pods
        """
        try:
            pods = self.core_v1.list_namespaced_pod(
                namespace=self.namespace,
                label_selector="app=lab-environment"
            )

            if not pods.items:
                print("No active sessions found")
                return []

            print(f"\nActive Sessions ({len(pods.items)}):")
            print("-" * 80)
            print(f"{'SESSION ID':<20} {'USER ID':<15} {'STATUS':<15} {'AGE'}")
            print("-" * 80)

            for pod in pods.items:
                session_id = pod.metadata.labels.get('session-id', 'N/A')
                user_id = pod.metadata.labels.get('user-id', 'N/A')
                status = pod.status.phase
                age = pod.metadata.creation_timestamp

                print(f"{session_id:<20} {user_id:<15} {status:<15} {age}")

            return pods.items

        except ApiException as e:
            print(f"Error listing sessions: {e.reason}")
            return []

    def get_session_status(self, session_id):
        """
        Get detailed status of a session

        Args:
            session_id: Session identifier

        Returns:
            dict: Session status information
        """
        pod_name = f"lab-session-{session_id}"

        try:
            pod = self.core_v1.read_namespaced_pod(
                name=pod_name,
                namespace=self.namespace
            )

            status = {
                'session_id': session_id,
                'user_id': pod.metadata.labels.get('user-id'),
                'phase': pod.status.phase,
                'created': pod.metadata.creation_timestamp,
                'containers': []
            }

            # Get container statuses
            if pod.status.container_statuses:
                for container in pod.status.container_statuses:
                    status['containers'].append({
                        'name': container.name,
                        'ready': container.ready,
                        'restart_count': container.restart_count,
                        'state': str(container.state)
                    })

            return status

        except ApiException as e:
            if e.status == 404:
                print(f"Session {session_id} not found")
            else:
                print(f"Error getting session status: {e.reason}")
            return None

    @staticmethod
    def _generate_password(length=32):
        """Generate a secure random password"""
        return secrets.token_urlsafe(length)


def main():
    parser = argparse.ArgumentParser(description='Manage Dozlab lab sessions')
    subparsers = parser.add_subparsers(dest='command', help='Commands')

    # Create command
    create_parser = subparsers.add_parser('create', help='Create a new session')
    create_parser.add_argument('--session-id', required=True, help='Session ID')
    create_parser.add_argument('--user-id', required=True, help='User ID')
    create_parser.add_argument('--rootfs-url', required=True, help='Rootfs image URL')
    create_parser.add_argument('--vm-cpu', type=int, default=1, help='VM CPUs')
    create_parser.add_argument('--vm-memory', type=int, default=1024, help='VM Memory (MB)')
    create_parser.add_argument('--namespace', default='default', help='Kubernetes namespace')

    # Delete command
    delete_parser = subparsers.add_parser('delete', help='Delete a session')
    delete_parser.add_argument('--session-id', required=True, help='Session ID')
    delete_parser.add_argument('--namespace', default='default', help='Kubernetes namespace')

    # List command
    list_parser = subparsers.add_parser('list', help='List all sessions')
    list_parser.add_argument('--namespace', default='default', help='Kubernetes namespace')

    # Status command
    status_parser = subparsers.add_parser('status', help='Get session status')
    status_parser.add_argument('--session-id', required=True, help='Session ID')
    status_parser.add_argument('--namespace', default='default', help='Kubernetes namespace')

    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        sys.exit(1)

    manager = DozlabSessionManager(namespace=args.namespace)

    if args.command == 'create':
        manager.create_session(
            session_id=args.session_id,
            user_id=args.user_id,
            rootfs_url=args.rootfs_url,
            vm_cpu=args.vm_cpu,
            vm_memory=args.vm_memory
        )

    elif args.command == 'delete':
        manager.delete_session(args.session_id)

    elif args.command == 'list':
        manager.list_sessions()

    elif args.command == 'status':
        status = manager.get_session_status(args.session_id)
        if status:
            print(yaml.dump(status, default_flow_style=False))


if __name__ == '__main__':
    main()
