/*
 * A text field in Tabbi's look (the pet's name, the Add a task field, an
 * API key): a 24 px field on the surface with a hairline stroke that
 * brightens on hover and takes the accent when focused, body text, an
 * optional leading symbol and a clear button that pops in while there is
 * text. Placeholder text sits in tertiary; nothing is ever cut off (the
 * field scrolls its own text, as fields do).
 */

import { useId, useRef, useState, type ChangeEvent, type CSSProperties, type InputHTMLAttributes, type KeyboardEvent } from "react";
import { tr } from "../../core/localization/tr";
import { useTransition } from "./context";
import { Icon } from "./Icon";
import { IconButton } from "./IconButton";
import { Tooltip } from "./Tooltip";

export interface TextFieldProps extends Omit<InputHTMLAttributes<HTMLInputElement>, "onChange" | "onSubmit" | "value" | "style" | "size"> {
  readonly value: string;
  readonly onChange: (value: string) => void;
  /** Called on Enter. */
  readonly onSubmit?: (value: string) => void;
  readonly label: string;
  readonly help?: string;
  readonly symbol?: string;
  readonly clearable?: boolean;
  readonly secure?: boolean;
  readonly width?: number | string;
  readonly preview?: "hover" | "focus";
  readonly style?: CSSProperties;
}

export function TextField({ value, onChange, onSubmit, label, help, symbol, clearable = true, secure = false, width, preview, className, disabled, style, ...rest }: TextFieldProps) {
  const id = useId();
  const input = useRef<HTMLInputElement>(null);
  const [focused, setFocused] = useState(false);
  const transition = useTransition("snappy", ["border-color", "box-shadow", "background-color"]);
  const onKeyDown = (event: KeyboardEvent<HTMLInputElement>) => {
    rest.onKeyDown?.(event);
    if (event.key === "Enter" && onSubmit) {
      onSubmit(value);
      event.preventDefault();
    } else if (event.key === "Escape" && clearable && value) {
      onChange("");
      event.preventDefault();
    }
  };
  return (
    <Tooltip text={help ?? label}>
      <div
        className={["kit-text-field", className].filter(Boolean).join(" ")}
        data-focused={focused || preview === "focus"}
        data-hover={preview === "hover" || undefined}
        data-disabled={disabled || undefined}
        style={{ width, transition, ...style }}
        onClick={() => input.current?.focus()}
      >
        {symbol && <Icon id={symbol} size={12} className="kit-text-field-symbol" />}
        <input
          {...rest}
          ref={input}
          id={id}
          type={secure ? "password" : "text"}
          className="kit-text-field-input"
          aria-label={label}
          value={value}
          disabled={disabled}
          onChange={(event: ChangeEvent<HTMLInputElement>) => onChange(event.target.value)}
          onFocus={(event) => {
            rest.onFocus?.(event);
            setFocused(true);
          }}
          onBlur={(event) => {
            rest.onBlur?.(event);
            setFocused(false);
          }}
          onKeyDown={onKeyDown}
        />
        {clearable && value.length > 0 && !disabled && (
          <IconButton symbol="close" size={16} help={tr("Clear")} className="kit-text-field-clear" tabIndex={-1} onClick={() => onChange("")} />
        )}
      </div>
    </Tooltip>
  );
}
