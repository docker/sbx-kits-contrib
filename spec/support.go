package spec

// Capability names one runtime ability a kit field needs beyond the core
// contract every runtime provides. A runtime declares the set it implements
// (CapabilitySet); EvaluateSupport reports the declared fields whose
// capability the runtime lacks. SPEC-v2.md §10 is the normative home.
type Capability string

const (
	// CapabilityHostKernel means sandboxes share the runtime host's kernel,
	// which is what makes security.privileged meaningful.
	CapabilityHostKernel Capability = "host-kernel"
	// CapabilityGPUSelector means the runtime applies sandbox.resources.gpu.
	CapabilityGPUSelector Capability = "gpu-selector"
	// CapabilityKitVolumes means the runtime auto-provisions the volumes
	// list with §5.7's identity: per (sandbox, kit, path), sized, reclaimed.
	CapabilityKitVolumes Capability = "kit-volumes"
	// CapabilityKitPorts means the runtime publishes the declared ports.
	CapabilityKitPorts Capability = "kit-ports"
	// CapabilityMixinAgentContext means the runtime delivers a mixin's
	// agentInstructions content per §4.2.
	CapabilityMixinAgentContext Capability = "mixin-agent-context"
)

// CapabilitySet declares the capabilities a runtime implements. A missing
// key reads as not implemented, so a runtime that declares nothing gets the
// full finding list for what a kit declares: the set fails closed.
type CapabilitySet map[Capability]bool

// SupportAction is what an applier MUST do with a declared field whose
// capability its runtime lacks. There is no silent tier: a field is applied
// with its specified semantics, refused, or visibly skipped.
type SupportAction string

const (
	// ActionRefuse fails the whole application, naming the field.
	ActionRefuse SupportAction = "refuse"
	// ActionWarn applies the rest of the kit and surfaces the skipped
	// field visibly (a warning, operation metadata) — never silently.
	ActionWarn SupportAction = "warn"
)

// SupportFinding reports one declared field the runtime cannot honour.
type SupportFinding struct {
	// Field is the dotted v2 grammar path (e.g. "security.privileged").
	Field string
	// Capability the runtime would need to honour the field.
	Capability Capability
	// Action the applier MUST take.
	Action SupportAction
	// Reason states why the field cannot be honoured without the capability.
	Reason string
	// Alternative names the portable way to get the effect, empty when
	// none exists.
	Alternative string
}

type supportRule struct {
	field       string
	capability  Capability
	declared    func(*Artifact) bool
	action      SupportAction
	reason      string
	alternative string
}

// supportRules is the per-field support ledger. A field with no rule needs
// no capability beyond the core contract and is honoured on every runtime;
// TestSupportLedgerCompleteness forces every grammar field to be classified
// one way or the other. The action encodes the field's failure severity:
// running a privileged workload unprivileged is a security divergence and
// refuses, while an undelivered convenience degrades with a visible skip.
var supportRules = []supportRule{
	{
		field:      v2Field("Security", "Privileged"),
		capability: CapabilityHostKernel,
		declared: func(a *Artifact) bool {
			return a.Manifest.Security != nil && a.Manifest.Security.Privileged
		},
		action: ActionRefuse,
		reason: "sandboxes on this runtime do not share a host kernel, so privileged cannot be honoured",
	},
	{
		field:      v2Field("Sandbox", "Resources", "GPU"),
		capability: CapabilityGPUSelector,
		declared: func(a *Artifact) bool {
			return a.Manifest.Resources != nil && a.Manifest.Resources.GPU != ""
		},
		action: ActionRefuse,
		reason: "this runtime does not apply the gpu selector, so declaring it would be silently inert",
	},
	{
		field:      v2Field("Volumes"),
		capability: CapabilityKitVolumes,
		declared: func(a *Artifact) bool {
			return len(a.Manifest.Volumes) > 0
		},
		action:      ActionWarn,
		reason:      "this runtime does not auto-provision kit volumes, so state under the declared paths would not persist",
		alternative: "attach a pre-created volume at create, or ship static content under files/",
	},
	{
		field:      v2Field("PublishedPorts"),
		capability: CapabilityKitPorts,
		declared: func(a *Artifact) bool {
			return len(a.PublishedPorts) > 0
		},
		action:      ActionWarn,
		reason:      "this runtime does not publish the declared ports",
		alternative: "publish the ports after create through the runtime's port controls",
	},
	{
		field:      v2Field("AgentInstructions", "Content"),
		capability: CapabilityMixinAgentContext,
		declared: func(a *Artifact) bool {
			return a.Manifest.Kind == KindMixin && a.AgentContext != ""
		},
		action:      ActionWarn,
		reason:      "this runtime does not deliver a mixin's agentInstructions content",
		alternative: "put shared instructions in the base kit's agentInstructions",
	},
}

// EvaluateSupport returns every field the artifact declares whose capability
// the runtime does not implement, in ledger order. An ActionRefuse finding
// MUST fail the application naming the field; an ActionWarn finding MUST be
// surfaced visibly. An empty result means the whole declaration is honoured.
func EvaluateSupport(a *Artifact, caps CapabilitySet) []SupportFinding {
	if a == nil {
		return nil
	}
	var findings []SupportFinding
	for _, rule := range supportRules {
		if caps[rule.capability] || !rule.declared(a) {
			continue
		}
		findings = append(findings, SupportFinding{
			Field:       rule.field,
			Capability:  rule.capability,
			Action:      rule.action,
			Reason:      rule.reason,
			Alternative: rule.alternative,
		})
	}
	return findings
}
