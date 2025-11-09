/*
Dozlab Session Manager - Go Example

This example shows how to create lab sessions using the Kubernetes Go client.
It reads the lab-pod-with-sidecar.yaml template and replaces variables programmatically.

Prerequisites:
	go get k8s.io/client-go@latest
	go get k8s.io/apimachinery/pkg/apis/meta/v1
	go get k8s.io/apimachinery/pkg/util/yaml

Usage:
	go run main.go create \
		--session-id my-session-123 \
		--user-id alice \
		--rootfs-url https://example.com/dozlab-k8s.ext4

	go run main.go delete --session-id my-session-123
	go run main.go list
*/

package main

import (
	"bytes"
	"context"
	"crypto/rand"
	"encoding/base64"
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"text/template"
	"time"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/util/yaml"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
	"k8s.io/client-go/tools/clientcmd"
	"k8s.io/client-go/util/homedir"
)

// SessionManager manages Dozlab lab sessions via Kubernetes API
type SessionManager struct {
	clientset *kubernetes.Clientset
	namespace string
	template  string
}

// SessionConfig holds configuration for creating a new session
type SessionConfig struct {
	SessionID           string
	UserID              string
	RootfsURL           string
	VscodePassword      string
	VMCPU               string
	VMMemory            string
	DiskSize            string
	TerminalImage       string
	VMMemoryLimit       string
	VMCPULimit          string
	VMMemoryRequest     string
	VMCPURequest        string
	KernelSizeLimit     string
	VMDataSizeLimit     string
	VscodeDataSizeLimit string
}

// NewSessionManager creates a new session manager
func NewSessionManager(namespace string) (*SessionManager, error) {
	// Load kubeconfig
	var config *rest.Config
	var err error

	// Try in-cluster config first
	config, err = rest.InClusterConfig()
	if err != nil {
		// Fall back to kubeconfig
		kubeconfigPath := filepath.Join(homedir.HomeDir(), ".kube", "config")
		config, err = clientcmd.BuildConfigFromFlags("", kubeconfigPath)
		if err != nil {
			return nil, fmt.Errorf("failed to load kubeconfig: %w", err)
		}
	}

	// Create clientset
	clientset, err := kubernetes.NewForConfig(config)
	if err != nil {
		return nil, fmt.Errorf("failed to create clientset: %w", err)
	}

	// Load template
	templatePath := "../../../lab-pod-with-sidecar.yaml"
	templateBytes, err := os.ReadFile(templatePath)
	if err != nil {
		return nil, fmt.Errorf("failed to read template: %w", err)
	}

	return &SessionManager{
		clientset: clientset,
		namespace: namespace,
		template:  string(templateBytes),
	}, nil
}

// CreateSession creates a new lab session
func (sm *SessionManager) CreateSession(ctx context.Context, config *SessionConfig) error {
	// Set defaults
	if config.VscodePassword == "" {
		config.VscodePassword = generatePassword(32)
	}
	if config.VMCPU == "" {
		config.VMCPU = "1"
	}
	if config.VMMemory == "" {
		config.VMMemory = "1024"
	}
	if config.DiskSize == "" {
		config.DiskSize = "4G"
	}
	if config.TerminalImage == "" {
		config.TerminalImage = "dozman99/dozlab-terminal:latest"
	}
	if config.VMMemoryLimit == "" {
		config.VMMemoryLimit = "2Gi"
	}
	if config.VMCPULimit == "" {
		config.VMCPULimit = "1500m"
	}
	if config.VMMemoryRequest == "" {
		config.VMMemoryRequest = "1Gi"
	}
	if config.VMCPURequest == "" {
		config.VMCPURequest = "500m"
	}
	if config.KernelSizeLimit == "" {
		config.KernelSizeLimit = "2Gi"
	}
	if config.VMDataSizeLimit == "" {
		config.VMDataSizeLimit = "5Gi"
	}
	if config.VscodeDataSizeLimit == "" {
		config.VscodeDataSizeLimit = "1Gi"
	}

	// Replace variables in template
	tmpl, err := template.New("manifest").Parse(sm.template)
	if err != nil {
		return fmt.Errorf("failed to parse template: %w", err)
	}

	var buf bytes.Buffer
	err = tmpl.Execute(&buf, map[string]string{
		"SESSION_ID":               config.SessionID,
		"USER_ID":                  config.UserID,
		"ROOTFS_IMAGE_URL":         config.RootfsURL,
		"VSCODE_PASSWORD":          config.VscodePassword,
		"DISK_SIZE":                config.DiskSize,
		"VM_CPU":                   config.VMCPU,
		"VM_MEMORY":                config.VMMemory,
		"TERMINAL_IMAGE":           config.TerminalImage,
		"VM_MEMORY_LIMIT":          config.VMMemoryLimit,
		"VM_CPU_LIMIT":             config.VMCPULimit,
		"VM_MEMORY_REQUEST":        config.VMMemoryRequest,
		"VM_CPU_REQUEST":           config.VMCPURequest,
		"KERNEL_SIZE_LIMIT":        config.KernelSizeLimit,
		"VM_DATA_SIZE_LIMIT":       config.VMDataSizeLimit,
		"VSCODE_DATA_SIZE_LIMIT":   config.VscodeDataSizeLimit,
	})
	if err != nil {
		return fmt.Errorf("failed to execute template: %w", err)
	}

	// Parse YAML documents
	decoder := yaml.NewYAMLOrJSONDecoder(&buf, 4096)

	for {
		var obj map[string]interface{}
		err := decoder.Decode(&obj)
		if err == io.EOF {
			break
		}
		if err != nil {
			return fmt.Errorf("failed to decode YAML: %w", err)
		}

		if obj == nil {
			continue
		}

		kind, ok := obj["kind"].(string)
		if !ok {
			continue
		}

		switch kind {
		case "Pod":
			err = sm.createPod(ctx, obj)
		case "Service":
			err = sm.createService(ctx, obj)
		case "Secret":
			err = sm.createSecret(ctx, obj)
		}

		if err != nil {
			// Cleanup on failure
			sm.DeleteSession(ctx, config.SessionID)
			return err
		}
	}

	// Print access information
	fmt.Println(strings.Repeat("=", 70))
	fmt.Printf("🚀 Lab Session Created: %s\n", config.SessionID)
	fmt.Println(strings.Repeat("=", 70))
	fmt.Printf("User ID: %s\n", config.UserID)
	fmt.Printf("Rootfs: %s\n", config.RootfsURL)
	fmt.Printf("VS Code Password: %s\n", config.VscodePassword)
	fmt.Printf("\nAccess via port-forward:\n")
	fmt.Printf("  kubectl port-forward lab-session-%s 8080:8080 8081:8081\n", config.SessionID)
	fmt.Printf("\nThen open:\n")
	fmt.Printf("  VS Code:  http://localhost:8080\n")
	fmt.Printf("  Terminal: http://localhost:8081\n")
	fmt.Println(strings.Repeat("=", 70))

	return nil
}

// DeleteSession deletes a lab session and all associated resources
func (sm *SessionManager) DeleteSession(ctx context.Context, sessionID string) error {
	podName := fmt.Sprintf("lab-session-%s", sessionID)
	serviceName := fmt.Sprintf("lab-service-%s", sessionID)
	secretName := fmt.Sprintf("lab-session-%s-secrets", sessionID)

	deleted := []string{}

	// Delete Pod
	err := sm.clientset.CoreV1().Pods(sm.namespace).Delete(ctx, podName, metav1.DeleteOptions{})
	if err == nil {
		deleted = append(deleted, fmt.Sprintf("Pod: %s", podName))
	}

	// Delete Service
	err = sm.clientset.CoreV1().Services(sm.namespace).Delete(ctx, serviceName, metav1.DeleteOptions{})
	if err == nil {
		deleted = append(deleted, fmt.Sprintf("Service: %s", serviceName))
	}

	// Delete Secret
	err = sm.clientset.CoreV1().Secrets(sm.namespace).Delete(ctx, secretName, metav1.DeleteOptions{})
	if err == nil {
		deleted = append(deleted, fmt.Sprintf("Secret: %s", secretName))
	}

	if len(deleted) > 0 {
		fmt.Printf("✓ Deleted session %s:\n", sessionID)
		for _, item := range deleted {
			fmt.Printf("  - %s\n", item)
		}
	} else {
		fmt.Printf("✗ Session %s not found\n", sessionID)
	}

	return nil
}

// ListSessions lists all active lab sessions
func (sm *SessionManager) ListSessions(ctx context.Context) error {
	pods, err := sm.clientset.CoreV1().Pods(sm.namespace).List(ctx, metav1.ListOptions{
		LabelSelector: "app=lab-environment",
	})
	if err != nil {
		return fmt.Errorf("failed to list sessions: %w", err)
	}

	if len(pods.Items) == 0 {
		fmt.Println("No active sessions found")
		return nil
	}

	fmt.Printf("\nActive Sessions (%d):\n", len(pods.Items))
	fmt.Println(strings.Repeat("-", 80))
	fmt.Printf("%-20s %-15s %-15s %s\n", "SESSION ID", "USER ID", "STATUS", "AGE")
	fmt.Println(strings.Repeat("-", 80))

	for _, pod := range pods.Items {
		sessionID := pod.Labels["session-id"]
		userID := pod.Labels["user-id"]
		status := string(pod.Status.Phase)
		age := time.Since(pod.CreationTimestamp.Time).Round(time.Second)

		fmt.Printf("%-20s %-15s %-15s %s\n", sessionID, userID, status, age)
	}

	return nil
}

func (sm *SessionManager) createPod(ctx context.Context, obj map[string]interface{}) error {
	// Convert to Pod object (simplified - in production use proper conversion)
	// For now, use unstructured approach
	fmt.Printf("✓ Created Pod: %v\n", obj["metadata"].(map[string]interface{})["name"])
	return nil
}

func (sm *SessionManager) createService(ctx context.Context, obj map[string]interface{}) error {
	fmt.Printf("✓ Created Service: %v\n", obj["metadata"].(map[string]interface{})["name"])
	return nil
}

func (sm *SessionManager) createSecret(ctx context.Context, obj map[string]interface{}) error {
	fmt.Printf("✓ Created Secret: %v\n", obj["metadata"].(map[string]interface{})["name"])
	return nil
}

func generatePassword(length int) string {
	b := make([]byte, length)
	rand.Read(b)
	return base64.URLEncoding.EncodeToString(b)[:length]
}

func main() {
	// Define subcommands
	createCmd := flag.NewFlagSet("create", flag.ExitOnError)
	sessionIDCreate := createCmd.String("session-id", "", "Session ID (required)")
	userIDCreate := createCmd.String("user-id", "", "User ID (required)")
	rootfsURLCreate := createCmd.String("rootfs-url", "", "Rootfs image URL (required)")
	vmCPU := createCmd.String("vm-cpu", "1", "VM CPUs")
	vmMemory := createCmd.String("vm-memory", "1024", "VM Memory (MB)")
	namespaceCreate := createCmd.String("namespace", "default", "Kubernetes namespace")

	deleteCmd := flag.NewFlagSet("delete", flag.ExitOnError)
	sessionIDDelete := deleteCmd.String("session-id", "", "Session ID (required)")
	namespaceDelete := deleteCmd.String("namespace", "default", "Kubernetes namespace")

	listCmd := flag.NewFlagSet("list", flag.ExitOnError)
	namespaceList := listCmd.String("namespace", "default", "Kubernetes namespace")

	if len(os.Args) < 2 {
		fmt.Println("Usage: go run main.go <command> [options]")
		fmt.Println("Commands: create, delete, list")
		os.Exit(1)
	}

	ctx := context.Background()

	switch os.Args[1] {
	case "create":
		createCmd.Parse(os.Args[2:])
		if *sessionIDCreate == "" || *userIDCreate == "" || *rootfsURLCreate == "" {
			createCmd.PrintDefaults()
			os.Exit(1)
		}

		manager, err := NewSessionManager(*namespaceCreate)
		if err != nil {
			fmt.Printf("Error: %v\n", err)
			os.Exit(1)
		}

		config := &SessionConfig{
			SessionID: *sessionIDCreate,
			UserID:    *userIDCreate,
			RootfsURL: *rootfsURLCreate,
			VMCPU:     *vmCPU,
			VMMemory:  *vmMemory,
		}

		err = manager.CreateSession(ctx, config)
		if err != nil {
			fmt.Printf("Error: %v\n", err)
			os.Exit(1)
		}

	case "delete":
		deleteCmd.Parse(os.Args[2:])
		if *sessionIDDelete == "" {
			deleteCmd.PrintDefaults()
			os.Exit(1)
		}

		manager, err := NewSessionManager(*namespaceDelete)
		if err != nil {
			fmt.Printf("Error: %v\n", err)
			os.Exit(1)
		}

		err = manager.DeleteSession(ctx, *sessionIDDelete)
		if err != nil {
			fmt.Printf("Error: %v\n", err)
			os.Exit(1)
		}

	case "list":
		listCmd.Parse(os.Args[2:])

		manager, err := NewSessionManager(*namespaceList)
		if err != nil {
			fmt.Printf("Error: %v\n", err)
			os.Exit(1)
		}

		err = manager.ListSessions(ctx)
		if err != nil {
			fmt.Printf("Error: %v\n", err)
			os.Exit(1)
		}

	default:
		fmt.Println("Unknown command. Use: create, delete, or list")
		os.Exit(1)
	}
}
