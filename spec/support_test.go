package spec

import (
	"reflect"
	"sort"
	"strings"
	"testing"
)

func TestEvaluateSupport(t *testing.T) {
	privileged := &Artifact{Manifest: Manifest{Kind: KindSandbox, Security: &Security{Privileged: true}}}
	gpu := &Artifact{Manifest: Manifest{Kind: KindSandbox, Resources: &Resources{GPU: "all"}}}
	volumes := &Artifact{Manifest: Manifest{Kind: KindSandbox, Volumes: []MountSpec{{Path: "/home/agent/.cache", Size: "2g"}}}}
	ports := &Artifact{Manifest: Manifest{Kind: KindSandbox}, PublishedPorts: []PublishedPort{{Container: 8080}}}
	mixinContext := &Artifact{Manifest: Manifest{Kind: KindMixin}, AgentContext: "use the tool"}
	sandboxContext := &Artifact{Manifest: Manifest{Kind: KindSandbox}, AgentContext: "use the tool"}

	none := CapabilitySet{}
	full := CapabilitySet{
		CapabilityHostKernel:        true,
		CapabilityGPUSelector:       true,
		CapabilityKitVolumes:        true,
		CapabilityKitPorts:          true,
		CapabilityMixinAgentContext: true,
	}

	cases := []struct {
		name string
		art  *Artifact
		caps CapabilitySet
		want []SupportFinding // Field+Action only; reasons asserted non-empty separately
	}{
		{name: "nil artifact yields nothing", art: nil, caps: none},
		{name: "empty artifact needs no capabilities", art: &Artifact{}, caps: none},
		{name: "privileged refused without host kernel", art: privileged, caps: none,
			want: []SupportFinding{{Field: "security.privileged", Action: ActionRefuse}}},
		{name: "privileged honoured with host kernel", art: privileged, caps: full},
		{name: "gpu refused without the selector capability", art: gpu, caps: none,
			want: []SupportFinding{{Field: "sandbox.resources.gpu", Action: ActionRefuse}}},
		{name: "gpu honoured with the selector capability", art: gpu, caps: full},
		{name: "volumes warn without auto-provisioning", art: volumes, caps: none,
			want: []SupportFinding{{Field: "volumes", Action: ActionWarn}}},
		{name: "volumes honoured with auto-provisioning", art: volumes, caps: full},
		{name: "ports warn without publication", art: ports, caps: none,
			want: []SupportFinding{{Field: "ports", Action: ActionWarn}}},
		{name: "ports honoured with publication", art: ports, caps: full},
		{name: "mixin agent context warns without delivery", art: mixinContext, caps: none,
			want: []SupportFinding{{Field: "agentInstructions.content", Action: ActionWarn}}},
		{name: "sandbox agent context needs no capability", art: sandboxContext, caps: none},
		{name: "nil capability set fails closed", art: privileged, caps: nil,
			want: []SupportFinding{{Field: "security.privileged", Action: ActionRefuse}}},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := EvaluateSupport(tc.art, tc.caps)
			if len(got) != len(tc.want) {
				t.Fatalf("got %d findings %+v, want %d", len(got), got, len(tc.want))
			}
			for i, w := range tc.want {
				if got[i].Field != w.Field || got[i].Action != w.Action {
					t.Errorf("finding %d = {%s %s}, want {%s %s}", i, got[i].Field, got[i].Action, w.Field, w.Action)
				}
				if got[i].Capability == "" {
					t.Errorf("finding %d has an empty capability", i)
				}
				if got[i].Reason == "" {
					t.Errorf("finding %d has an empty reason", i)
				}
			}
		})
	}
}

// TestSupportLedgerCompleteness forces every v2 grammar field to be
// classified: either listed as needing no capability beyond the core
// contract, or covered by a supportRules entry. Adding a grammar field
// without classifying it fails here, which is the ledger's drift alarm
// (same role TestFieldPaths plays for message paths).
func TestSupportLedgerCompleteness(t *testing.T) {
	core := map[string]bool{
		"schemaVersion": true, "kind": true, "name": true, "version": true,
		"displayName": true, "description": true, "sourceURL": true,
		"extends": true, "mixins": true, "requires.agent": true,
		"locked": true, "licenses": true, "args": true,
		"sandbox.image":      true,
		"sandbox.entrypoint": true, "sandbox.command": true,
		"sandbox.resources.cpu": true, "sandbox.resources.memory": true,
		"agentInstructions.filename": true,
		"permissions.network.allow":  true, "permissions.network.deny": true,
		"credentials": true, "environment.variables": true,
		"environment.proxyManaged": true, // legacy input; normalize folds it into credentials
		"setup.install":            true, "setup.startup": true, "setup.files": true,
		// build is forward-compat: accepted at decode, rejected at load when
		// image is absent, uniformly on every runtime (see Manifest.Build).
		"sandbox.build.context": true, "sandbox.build.dockerfile": true,
		"sandbox.build.args": true, "sandbox.build.target": true,
		"sandbox.build.platforms": true,
	}
	ruled := map[string]bool{}
	for _, r := range supportRules {
		ruled[r.field] = true
	}

	var unclassified []string
	for _, path := range grammarPaths(specFileV2Type, "") {
		if !core[path] && !ruled[path] {
			unclassified = append(unclassified, path)
		}
	}
	sort.Strings(unclassified)
	if len(unclassified) > 0 {
		t.Fatalf("grammar fields missing a support classification (add to supportRules or to the core list): %v", unclassified)
	}
	for field := range ruled {
		if core[field] {
			t.Errorf("field %q is both ruled and listed as core", field)
		}
	}
}

// grammarPaths walks a grammar struct's yaml-tagged fields, recursing into
// struct and pointer-to-struct fields and stopping at scalars, slices, and
// maps, mirroring the granularity the support ledger classifies at.
func grammarPaths(t reflect.Type, prefix string) []string {
	for t.Kind() == reflect.Pointer {
		t = t.Elem()
	}
	var paths []string
	for i := range t.NumField() {
		f := t.Field(i)
		if !f.IsExported() && f.Anonymous {
			continue
		}
		tag, _, _ := strings.Cut(f.Tag.Get("yaml"), ",")
		if tag == "" || tag == "-" {
			continue
		}
		path := tag
		if prefix != "" {
			path = prefix + "." + tag
		}
		ft := f.Type
		for ft.Kind() == reflect.Pointer {
			ft = ft.Elem()
		}
		if ft.Kind() == reflect.Struct && ft.NumField() > 0 && hasYAMLFields(ft) {
			paths = append(paths, grammarPaths(ft, path)...)
			continue
		}
		paths = append(paths, path)
	}
	return paths
}

func hasYAMLFields(t reflect.Type) bool {
	for i := range t.NumField() {
		tag, _, _ := strings.Cut(t.Field(i).Tag.Get("yaml"), ",")
		if tag != "" && tag != "-" {
			return true
		}
	}
	return false
}
