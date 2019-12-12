import java
import semmle.code.java.dataflow.TaintTracking
import foo

/** The method `read` of `HttpMessageConverter`. */
class Read extends Method {
  Read() {
    this.hasName("read") and
    this.getDeclaringType().getSourceDeclaration().hasQualifiedName("org.springframework.http.converter", "HttpMessageConverter")
  }
}

/** The class `HttpInputMessage` */
class HttpInputMessage extends RefType {
  HttpInputMessage() {
    this.hasQualifiedName("org.springframework.http", "HttpInputMessage")
  }
}

class SpringHttpMessageConverterConfig extends TaintTracking::Configuration {
  SpringHttpMessageConverterConfig() {
    this = "SpringHttpMessageConverterConfig"
  }
  
  override predicate isSource(DataFlow::Node source) {
    //The `HttpInputMessage` argument in a `HttpMessageConverter`.*/
    exists(Method m, Read r, Parameter p | m.overrides*(r) and
      p = m.getAParameter() and p.getType() instanceof HttpInputMessage and
      source.asExpr() = p.getAnAccess()
    )
  }
  
  override predicate isSink(DataFlow::Node sink) {
    // Castor deserialization method 
    exists(MethodAccess ma |
      ma.getMethod().hasName("unmarshal") and
      ma.getMethod().getDeclaringType().hasQualifiedName("org.exolab.castor.xml", "Unmarshaller") and
      sink.asExpr() = ma.getAnArgument()
    ) or
    // Hessian deserialization method.
    exists(MethodAccess ma |
      ma.getMethod().hasName("readObject") and
      ma.getMethod().getDeclaringType().hasQualifiedName("com.caucho.hessian.io","AbstractHessianInput") and
      sink.asExpr() = ma.getQualifier()
    )
  }
  
  override predicate isAdditionalTaintStep(DataFlow::Node node1, DataFlow::Node node2) {
    exists(ClassInstanceExpr ctor | 
      ctor.getAnArgument() = node1.asExpr() and //Source of this step is the argument
      ctor.getNumArgument() = 1 and
      (
        ctor.getConstructedType().(RefType).hasQualifiedName("com.caucho.io", "HessianInput") or
        ctor.getConstructedType().(RefType).hasQualifiedName("com.caucho.io", "Hessian2Input")
      ) and
      node2.asExpr() = ctor
    ) or
    //If an `HttpInputMessage` is tainted, then the result of `getBody` is also tainted. */
    exists(MethodAccess ma | 
      ma.getMethod().hasName("getBody") and
      ma.getMethod().getDeclaringType() instanceof HttpInputMessage and
      node1.asExpr() = ma.getQualifier() and
      node2.asExpr() = ma
    )
  }
}

class BuildConstraintViolationWithTemplateMethod extends Method {
  BuildConstraintViolationWithTemplateMethod() {
    getDeclaringType().getASupertype*().hasQualifiedName("javax.validation", "ConstraintValidatorContext") and
    (
      hasName("buildConstraintViolationWithTemplate") or
      hasName("getNamespace") or
      hasName("getActionName")
    )
  }
}


from SpringHttpMessageConverterConfig cfg, DataFlow::Node source, DataFlow::Node sink
where cfg.hasFlow(source, sink)
select source, sink




